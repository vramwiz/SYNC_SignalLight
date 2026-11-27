unit SignalLight_Raster;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 信号機の論理座標から平滑化したRGBAを生成する。原点は画像の中心。
// 画素と部分キャッシュは描画器が所有する。画像はストレートアルファで保持する。

interface

uses System.Types, AviUtl2FilterTypes;

type
  TSignalColor = record R, G, B: Double end;
  TSignalPixels = array of TPIXEL_RGBA;

  TSignalPatch = record
    Bounds: TRect;
    Pixels: TSignalPixels;
  end;

  TSignalCanvas = class
  private
    FWidth, FHeight: Integer;
    FScale, FStep: Double;
    FPixels: TSignalPixels;
  public
    // 幅と高さは100%時の半寸法。描画座標の原点を中心画素間へそろえる。
    procedure Reset(HalfWidth, HalfHeight, Scale: Double);
    function PixelBounds(L, T, R, B: Double): TRect;
    function XAt(X: Integer): Double; inline;
    function YAt(Y: Integer): Double; inline;
    // 画素座標はPixelBoundsでクリップ済みのものを指定する。
    procedure Blend(X, Y: Integer; const Color: TSignalColor; Alpha: Double); inline;
    // 各寸法は論理座標。グラデーションの色は上端から下端、または左端から右端。
    procedure RoundBox(CX, CY, HW, HH, Radius: Double;
      const First, Last: TSignalColor; Horizontal: Boolean = False);
    procedure Ellipse(CX, CY, RX, RY: Double;
      const Top, Bottom: TSignalColor; Opacity: Double = 1);
    procedure Halo(CX, CY, RX, RY: Double; const Color: TSignalColor; Opacity: Double);
    // 変化する領域のみ退避・復帰する。配列を持つPatchは呼出側が所有する。
    procedure SavePatch(var Patch: TSignalPatch; const Area: TRect);
    procedure RestorePatch(const Patch: TSignalPatch);
    // SetImageDataに渡すための借用ポインター。Resetまたは破棄まで有効。
    function PixelData: PPIXEL_RGBA;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Scale: Double read FScale;
  end;

function UnitValue(Value: Double): Double; inline;
function SmoothUnit(Value: Double): Double; inline;
function SignalColor(Code: Cardinal): TSignalColor;
function MixColor(const A, B: TSignalColor; Amount: Double): TSignalColor; inline;
function ScaleColor(const Color: TSignalColor; Amount: Double): TSignalColor; inline;
function TintColor(const A, B: TSignalColor): TSignalColor; inline;
function BoxDistance(X, Y, HW, HH, Radius: Double): Double; inline;

implementation

uses System.Math;

function UnitValue(Value: Double): Double;
begin
  if Value < 0 then Exit(0);
  if Value > 1 then Exit(1);
  Result := Value;
end;

function SmoothUnit(Value: Double): Double;
begin
  Value := UnitValue(Value);
  Result := Value * Value * (3 - 2 * Value);
end;

function SignalColor(Code: Cardinal): TSignalColor;
begin
  Result.R := ((Code shr 16) and 255) / 255;
  Result.G := ((Code shr 8) and 255) / 255;
  Result.B := (Code and 255) / 255;
end;

function MixColor(const A, B: TSignalColor; Amount: Double): TSignalColor;
begin
  Result.R := A.R + (B.R - A.R) * Amount;
  Result.G := A.G + (B.G - A.G) * Amount;
  Result.B := A.B + (B.B - A.B) * Amount;
end;

function ScaleColor(const Color: TSignalColor; Amount: Double): TSignalColor;
begin
  Result.R := Color.R * Amount;
  Result.G := Color.G * Amount;
  Result.B := Color.B * Amount;
end;

function TintColor(const A, B: TSignalColor): TSignalColor;
begin
  Result.R := A.R * B.R;
  Result.G := A.G * B.G;
  Result.B := A.B * B.B;
end;

function BoxDistance(X, Y, HW, HH, Radius: Double): Double;
var
  DX, DY: Double;
begin
  DX := Abs(X) - HW + Radius;
  DY := Abs(Y) - HH + Radius;
  if (DX > 0) and (DY > 0) then
    Result := Sqrt(Sqr(DX) + Sqr(DY)) - Radius
  else
    Result := Max(DX, DY) - Radius;
end;

procedure TSignalCanvas.Reset(HalfWidth, HalfHeight, Scale: Double);
begin
  FScale := Scale;
  FStep := 1 / Scale;
  FWidth := 2 * Ceil(HalfWidth * Scale);
  FHeight := 2 * Ceil(HalfHeight * Scale);
  SetLength(FPixels, FWidth * FHeight);
  FillChar(FPixels[0], Length(FPixels) * SizeOf(TPIXEL_RGBA), 0);
end;

function TSignalCanvas.PixelBounds(L, T, R, B: Double): TRect;
begin
  Result.Left := Max(0, Floor(L * FScale + FWidth * 0.5) - 1);
  Result.Top := Max(0, Floor(T * FScale + FHeight * 0.5) - 1);
  Result.Right := Min(FWidth, Ceil(R * FScale + FWidth * 0.5) + 1);
  Result.Bottom := Min(FHeight, Ceil(B * FScale + FHeight * 0.5) + 1);
end;

function TSignalCanvas.XAt(X: Integer): Double;
begin
  Result := (X + 0.5 - FWidth * 0.5) * FStep;
end;

function TSignalCanvas.YAt(Y: Integer): Double;
begin
  Result := (Y + 0.5 - FHeight * 0.5) * FStep;
end;

procedure TSignalCanvas.Blend(X, Y: Integer; const Color: TSignalColor; Alpha: Double);
var
  P: PPIXEL_RGBA;
  A, Weight, R, G, B: Double;
begin
  if Alpha < 0.5 / 255 then Exit;
  P := @FPixels[Y * FWidth + X];
  R := UnitValue(Color.R) * 255;
  G := UnitValue(Color.G) * 255;
  B := UnitValue(Color.B) * 255;
  if (Alpha >= 1) or (P^.A = 0) then
  begin
    P^.R := Round(R);
    P^.G := Round(G);
    P^.B := Round(B);
    P^.A := Round(UnitValue(Alpha) * 255);
    Exit;
  end;
  A := Alpha + P^.A / 255 * (1 - Alpha);
  Weight := Alpha / A;
  P^.R := Round(P^.R + (R - P^.R) * Weight);
  P^.G := Round(P^.G + (G - P^.G) * Weight);
  P^.B := Round(P^.B + (B - P^.B) * Weight);
  P^.A := Round(A * 255);
end;

procedure TSignalCanvas.RoundBox(CX, CY, HW, HH, Radius: Double;
  const First, Last: TSignalColor; Horizontal: Boolean);
var
  Area: TRect;
  X, Y: Integer;
  PX, PY, Coverage: Double;
  Color: TSignalColor;
begin
  Area := PixelBounds(CX - HW, CY - HH, CX + HW, CY + HH);
  for Y := Area.Top to Area.Bottom - 1 do
  begin
    PY := YAt(Y) - CY;
    Color := MixColor(First, Last, UnitValue((PY + HH) / (2 * HH)));
    for X := Area.Left to Area.Right - 1 do
    begin
      PX := XAt(X) - CX;
      Coverage := UnitValue(0.5 - BoxDistance(PX, PY, HW, HH, Radius) * FScale);
      if Coverage <= 0 then Continue;
      if Horizontal then
        Color := MixColor(First, Last, UnitValue((PX + HW) / (2 * HW)));
      Blend(X, Y, Color, Coverage);
    end;
  end;
end;

procedure TSignalCanvas.Ellipse(CX, CY, RX, RY: Double;
  const Top, Bottom: TSignalColor; Opacity: Double);
var
  Area: TRect;
  X, Y: Integer;
  NY, NY2, InvRX, EdgeScale, D: Double;
  Color: TSignalColor;
begin
  Area := PixelBounds(CX - RX, CY - RY, CX + RX, CY + RY);
  InvRX := 1 / RX;
  EdgeScale := Min(RX, RY) * FScale;
  for Y := Area.Top to Area.Bottom - 1 do
  begin
    NY := (YAt(Y) - CY) / RY;
    NY2 := Sqr(NY);
    Color := MixColor(Top, Bottom, UnitValue(0.5 + NY * 0.5));
    for X := Area.Left to Area.Right - 1 do
    begin
      D := Sqrt(Sqr((XAt(X) - CX) * InvRX) + NY2);
      Blend(X, Y, Color, Opacity * UnitValue(0.5 + (1 - D) * EdgeScale));
    end;
  end;
end;

procedure TSignalCanvas.Halo(CX, CY, RX, RY: Double; const Color: TSignalColor;
  Opacity: Double);
var
  Area: TRect;
  X, Y: Integer;
  DY2, D2, Falloff, InvRX: Double;
begin
  Area := PixelBounds(CX - RX, CY - RY, CX + RX, CY + RY);
  InvRX := 1 / RX;
  for Y := Area.Top to Area.Bottom - 1 do
  begin
    DY2 := Sqr((YAt(Y) - CY) / RY);
    for X := Area.Left to Area.Right - 1 do
    begin
      D2 := Sqr((XAt(X) - CX) * InvRX) + DY2;
      if D2 >= 1 then Continue;
      Falloff := 1 - D2;
      Blend(X, Y, Color, Opacity * Sqr(Falloff) * Falloff);
    end;
  end;
end;

procedure TSignalCanvas.SavePatch(var Patch: TSignalPatch; const Area: TRect);
var
  Y, RowWidth: Integer;
begin
  Patch.Bounds := Area;
  RowWidth := Area.Width;
  SetLength(Patch.Pixels, RowWidth * Area.Height);
  for Y := Area.Top to Area.Bottom - 1 do
    Move(FPixels[Y * FWidth + Area.Left], Patch.Pixels[(Y - Area.Top) * RowWidth],
      RowWidth * SizeOf(TPIXEL_RGBA));
end;

procedure TSignalCanvas.RestorePatch(const Patch: TSignalPatch);
var
  Y, RowWidth: Integer;
begin
  RowWidth := Patch.Bounds.Width;
  for Y := Patch.Bounds.Top to Patch.Bounds.Bottom - 1 do
    Move(Patch.Pixels[(Y - Patch.Bounds.Top) * RowWidth],
      FPixels[Y * FWidth + Patch.Bounds.Left], RowWidth * SizeOf(TPIXEL_RGBA));
end;

function TSignalCanvas.PixelData: PPIXEL_RGBA;
begin
  Result := @FPixels[0];
end;

end.

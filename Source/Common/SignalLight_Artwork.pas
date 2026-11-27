unit SignalLight_Artwork;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 筐体、支柱、レンズ、人物シルエットと残り時間の目盛りを内部描画する。
// 図形は100%時の論理座標で定義し、描画時にピクセル密度を変える。

interface

uses System.Types, SignalLight_Settings, SignalLight_Raster;

const
  LAMP_PATCH_RADIUS = 68;

type
  TSignalWaitColumn = (swLeft, swRight);

  TSignalLayout = record
    BodyHW, BodyHH, HalfWidth, HalfHeight, PoleX: Double;
    Lamps: array[slRed..slYellow] of TPointF;
  end;

  TSignalLightLevel = record
    Day, Twilight: Double;
  end;

// 種類と付属物から描画範囲を求める。すべての構成で原点は灯器本体の中心。
function MakeLayout(const A: TSignalAppearance): TSignalLayout;
// 十進の時刻から昼光と朝夕の寄与をそれぞれ0～1で返す。
function SampleLight(Hour: Double): TSignalLightLevel;

// 消灯した灯器を透明なキャンバスに描く。
procedure DrawHousing(Canvas: TSignalCanvas; const A: TSignalAppearance;
  const Layout: TSignalLayout; const Light: TSignalLightLevel);
// 指定の灯火を、消灯した灯器の対応領域へ描く。Tintは点灯部分に掛ける$RRGGBB。
procedure DrawLitLamp(Canvas: TSignalCanvas; const A: TSignalAppearance;
  const Layout: TSignalLayout; const Light: TSignalLightLevel;
  Lamp: TSignalLamp; Tint: Cardinal);
// 灯火とグローの上に目盛りを合成する。CenterYは表示するレンズの論理座標。
// 同じ範囲を退避・復帰できるよう、目盛りの描画位置と部分キャッシュの範囲をそろえる。
function WaitColumnArea(Canvas: TSignalCanvas; CenterY: Double;
  Column: TSignalWaitColumn): TRect;
procedure DrawWaitColumn(Canvas: TSignalCanvas; CenterY: Double;
  const Light: TSignalLightLevel; Column: TSignalWaitColumn; OnTopLens: Boolean;
  Count: Integer);

implementation

uses System.Math, AviUtl2FilterTypes;

const
  LAMP_RADIUS = 32;
  PEDESTRIAN_RX = 34;
  PEDESTRIAN_RY = 30;
  LED_PITCH = 5.2;
  WAIT_COLUMN_X: array[TSignalWaitColumn] of Double = (-26.6, 26.6);
  WAIT_COLUMN_HW = 4.4;
  WAIT_COLUMN_HH = 26;
  WAIT_LED_PITCH = 4.85;
  WAIT_LED_TOP_COLOR: array[Boolean] of Cardinal = ($FF6B56, $53FFDB);
  WAIT_LED_BOTTOM_COLOR: array[Boolean] of Cardinal = ($B61A14, $179B80);

type
  TIconStroke = record
    X1, Y1, X2, Y2, Radius: Double;
  end;

const
  STANDING: array[0..4] of TIconStroke = (
    (X1: 0; Y1: -10; X2: 0; Y2: 5; Radius: 4.4),
    (X1: -3; Y1: -9; X2: -9; Y2: 4; Radius: 2.4),
    (X1: 3; Y1: -9; X2: 9; Y2: 4; Radius: 2.4),
    (X1: -2.6; Y1: 4; X2: -3.8; Y2: 22; Radius: 2.7),
    (X1: 2.6; Y1: 4; X2: 3.8; Y2: 22; Radius: 2.7));
  WALKING: array[0..8] of TIconStroke = (
    (X1: 3; Y1: -11; X2: -2; Y2: 3; Radius: 4),
    (X1: 2; Y1: -10; X2: 7.5; Y2: -3; Radius: 2.1),
    (X1: 7.5; Y1: -3; X2: 15; Y2: -4; Radius: 2.1),
    (X1: 0; Y1: -10; X2: -8; Y2: -5; Radius: 2.1),
    (X1: -8; Y1: -5; X2: -12; Y2: 2; Radius: 2.1),
    (X1: -2; Y1: 3; X2: 6; Y2: 11; Radius: 2.8),
    (X1: 6; Y1: 11; X2: 12; Y2: 21; Radius: 2.6),
    (X1: -2; Y1: 3; X2: -7; Y2: 14; Radius: 2.8),
    (X1: -7; Y1: 14; X2: -14; Y2: 21; Radius: 2.6));

function MakeLayout(const A: TSignalAppearance): TSignalLayout;
begin
  Result := Default(TSignalLayout);
  case A.Kind of
    skHorizontal:
      begin
        Result.BodyHW := 148;
        Result.BodyHH := 51;
        Result.PoleX := -122;
        Result.Lamps[slGreen] := PointF(-92, 0);
        Result.Lamps[slYellow] := PointF(0, 0);
        Result.Lamps[slRed] := PointF(92, 0);
      end;
    skVertical:
      begin
        Result.BodyHW := 54;
        Result.BodyHH := 142;
        Result.Lamps[slRed] := PointF(0, -85);
        Result.Lamps[slYellow] := PointF(0, 0);
        Result.Lamps[slGreen] := PointF(0, 85);
      end;
    skPedestrian, skPedestrianWait:
      begin
        Result.BodyHW := 55;
        Result.BodyHH := 94;
        Result.Lamps[slRed] := PointF(0, -42);
        Result.Lamps[slGreen] := PointF(0, 42);
      end;
  end;
  // 灯器の中心を維持したまま、支柱や周辺光が収まる対称な画像範囲を取る。
  Result.HalfWidth := Max(Result.BodyHW + 10,
    Abs(Result.Lamps[slRed].X) + LAMP_PATCH_RADIUS);
  Result.HalfHeight := Max(Result.BodyHH + 9,
    Abs(Result.Lamps[slRed].Y) + LAMP_PATCH_RADIUS);
  if A.PoleLength > 0 then
    Result.HalfHeight := Max(Result.HalfHeight, Result.BodyHH + A.PoleLength + 4);
end;

function SampleLight(Hour: Double): TSignalLightLevel;
var
  Elevation: Double;
begin
  Elevation := Cos((Hour - 12) * (2 * Pi / 24));
  Result.Day := SmoothUnit((Elevation + 0.16) / 0.52);
  Result.Twilight := Sqr(1 - SmoothUnit(Abs(Elevation - 0.015) / 0.40));
end;

function SurfaceColor(Code: Cardinal; const Light: TSignalLightLevel): TSignalColor;
var
  Base: TSignalColor;
begin
  Base := SignalColor(Code);
  Result := MixColor(TintColor(Base, SignalColor($899DBC)), Base, Light.Day);
  Result := ScaleColor(Result, 0.30 + 0.70 * Light.Day + 0.19 * Light.Twilight);
  Result := MixColor(Result, TintColor(Base, SignalColor($FFAD77)), 0.33 * Light.Twilight);
end;

procedure Fastener(Canvas: TSignalCanvas; X, Y: Double; const Base: TSignalColor);
var
  Metal: TSignalColor;
begin
  Metal := ScaleColor(Base, 1.35);
  Canvas.Ellipse(X + 0.3, Y + 0.7, 3.1, 3.1, ScaleColor(Base, 0.40), ScaleColor(Base, 0.55));
  Canvas.Ellipse(X, Y, 2.5, 2.5, Metal, ScaleColor(Base, 0.78));
  Canvas.RoundBox(X, Y + 0.1, 1.5, 0.44, 0.4, ScaleColor(Base, 0.42), ScaleColor(Base, 0.62));
end;

procedure DrawPole(Canvas: TSignalCanvas; CenterX, Top, Length: Double; const Base: TSignalColor);
const
  HALF_WIDTH = 12;
var
  BodyEnd, XPart, YPart, Curvature, Reflection, Edge, CenterY: Double;
  Area: TRect;
  X, Y: Integer;
  Metal: TSignalColor;
begin
  // 正面から見た円柱の投影。横方向の曲率とハイライトで丸みを表す。
  CenterY := Top + Length * 0.5;
  BodyEnd := Top + Length;
  Area := Canvas.PixelBounds(CenterX - HALF_WIDTH, Top, CenterX + HALF_WIDTH, BodyEnd);
  for X := Area.Left to Area.Right - 1 do
  begin
    XPart := (Canvas.XAt(X) - CenterX) / HALF_WIDTH;
    Curvature := Sqrt(Max(0.0, 1 - Sqr(XPart)));
    Reflection := Sqr(Max(0.0, 1 - Abs(XPart + 0.34) * 2.1));
    Metal := ScaleColor(Base, 0.42 + 0.62 * Curvature - 0.17 * XPart + 0.35 * Reflection);
    for Y := Area.Top to Area.Bottom - 1 do
    begin
      YPart := Canvas.YAt(Y) - CenterY;
      Edge := 0.5 - BoxDistance(XPart * HALF_WIDTH, YPart, HALF_WIDTH,
        Length * 0.5, Min(2.4, Length * 0.5)) * Canvas.Scale;
      Canvas.Blend(X, Y, Metal, UnitValue(Edge));
    end;
  end;
  if Length >= 10 then
  begin
    Canvas.Ellipse(CenterX, BodyEnd - 1.3, HALF_WIDTH - 0.5, 2.0,
      ScaleColor(Base, 0.69), ScaleColor(Base, 0.43));
    Canvas.RoundBox(CenterX + 0.3, Top + 6.5, 14.6, 4, 1.6,
      ScaleColor(Base, 1.26), ScaleColor(Base, 0.49), True);
  end;
end;

procedure GetLensSize(Kind: TSignalKind; out RX, RY: Double);
begin
  RX := LAMP_RADIUS;
  RY := LAMP_RADIUS;
  if IsPedestrian(Kind) then
  begin
    RX := PEDESTRIAN_RX;
    RY := PEDESTRIAN_RY;
  end;
end;

procedure DrawBezel(Canvas: TSignalCanvas; Kind: TSignalKind;
  const P: TPointF; const Body, Shade: TSignalColor; ShowHood: Boolean);
var
  RX, RY: Double;
  Rim, Dark: TSignalColor;
begin
  GetLensSize(Kind, RX, RY);
  Rim := ScaleColor(Body, 0.56);
  Dark := ScaleColor(Body, 0.18);
  if IsPedestrian(Kind) then
  begin
    if ShowHood then
    begin
      Canvas.RoundBox(P.X + 1, P.Y - 11, RX + 7, RY + 7, 13,
        ScaleColor(Shade, 1.22), ScaleColor(Shade, 0.37));
      Canvas.RoundBox(P.X, P.Y - 7.4, RX + 4.7, RY + 6, 12,
        ScaleColor(Shade, 0.28), ScaleColor(Shade, 0.68));
    end;
    Canvas.RoundBox(P.X, P.Y + 0.7, RX + 3.3, RY + 3.4, 9.5, Rim, Dark);
    Canvas.RoundBox(P.X, P.Y, RX + 1.2, RY + 1.2, 8, Dark, ScaleColor(Rim, 1.48));
  end
  else
  begin
    if ShowHood then
    begin
      Canvas.Ellipse(P.X + 1.8, P.Y - 11.2, RX + 7.4, RY + 7.2,
        ScaleColor(Shade, 1.27), ScaleColor(Shade, 0.38));
      Canvas.Ellipse(P.X, P.Y - 8, RX + 5, RY + 6.8,
        ScaleColor(Shade, 0.33), ScaleColor(Shade, 0.79));
    end;
    Canvas.Ellipse(P.X, P.Y + 1.2, RX + 4, RY + 4, Rim, Dark);
    Canvas.Ellipse(P.X, P.Y, RX + 1.4, RY + 1.4, Dark, ScaleColor(Rim, 1.48));
  end;
end;

function IconDistance(X, Y, HeadX: Double; const Strokes: array of TIconStroke): Double;
var
  Stroke: TIconStroke;
  DX, DY, FromX, FromY, Along, D: Double;
begin
  Result := Sqrt(Sqr(X - HeadX) + Sqr(Y + 19.5)) - 4.15;
  if Result < -1 then Exit;
  for Stroke in Strokes do
  begin
    DX := Stroke.X2 - Stroke.X1;
    DY := Stroke.Y2 - Stroke.Y1;
    FromX := X - Stroke.X1;
    FromY := Y - Stroke.Y1;
    Along := UnitValue((FromX * DX + FromY * DY) / (Sqr(DX) + Sqr(DY)));
    D := Sqrt(Sqr(FromX - DX * Along) + Sqr(FromY - DY * Along)) - Stroke.Radius;
    Result := Min(Result, D);
    if Result < -2 then Exit;
  end;
end;

function LampColor(Lamp: TSignalLamp): TSignalColor;
const
  CODES: array[slNone..slYellow] of Cardinal = ($000000, $FF2619, $21F0BD, $FFB522);
begin
  Result := SignalColor(CODES[Lamp]);
end;

procedure DrawLens(Canvas: TSignalCanvas; const A: TSignalAppearance;
  const P: TPointF; const Light: TSignalLightLevel; Lamp: TSignalLamp;
  Lit: Boolean; const Tint: TSignalColor);
var
  Area: TRect;
  X, Y: Integer;
  RX, RY, Py, Px, U, V, R2, Edge, Coverage, Pattern, Detail, Specular,
    RowLED, ColLED, Dot, Icon, D, Brightness, Emission: Double;
  Base, Hue, Hot, Glass, Lens: TSignalColor;
begin
  GetLensSize(A.Kind, RX, RY);
  Area := Canvas.PixelBounds(P.X - RX, P.Y - RY, P.X + RX, P.Y + RY);
  Hue := LampColor(Lamp);
  Hot := MixColor(Hue, SignalColor($FFF3DA), 0.77);
  if Lit then
  begin
    Hue := TintColor(Hue, Tint);
    Hot := TintColor(Hot, Tint);
  end;
  Glass := MixColor(SignalColor($091014), SignalColor($758894), Light.Day * 0.55);
  Glass := MixColor(Glass, SignalColor($997553), Light.Twilight * 0.23);
  Base := MixColor(ScaleColor(Glass, 0.55), Hue, 0.055 + 0.072 * Light.Day);
  Brightness := 1.05 + 0.23 * (1 - Light.Day);
  // 縮小時はLEDの間隔が1画素に近づくので、点の明暗差を抑えてちらつきを減らす。
  Detail := SmoothUnit((Canvas.Scale * LED_PITCH - 1.2) / 2.2);
  for Y := Area.Top to Area.Bottom - 1 do
  begin
    Py := Canvas.YAt(Y) - P.Y;
    V := Py / RY;
    RowLED := Sqr(Py - LED_PITCH * Round(Py / LED_PITCH));
    for X := Area.Left to Area.Right - 1 do
    begin
      Px := Canvas.XAt(X) - P.X;
      U := Px / RX;
      R2 := Sqr(U) + Sqr(V);
      if IsPedestrian(A.Kind) then
        Edge := BoxDistance(Px, Py, RX, RY, 7)
      else
        Edge := (Sqrt(R2) - 1) * RY;
      Coverage := UnitValue(0.5 - Edge * Canvas.Scale);
      if Coverage <= 0 then Continue;

      // 昼は空の反射と消灯色が残り、夜はレンズ面の反射が弱くなる。
      Specular := 0.17 * Sqr(UnitValue(1 - Sqr((U + 0.26) * 1.25) -
        Sqr((V + 0.52) * 3.7)));
      Lens := ScaleColor(Base, 0.70 + 0.52 * UnitValue(1 - R2));
      Lens := MixColor(Lens, Glass, Specular * (0.38 + 1.74 * Light.Day));

      Icon := 1;
      if IsPedestrian(A.Kind) then
      begin
        Icon := 0;
        if (Abs(Px) < 19) and (Abs(Py) < 27) then
        begin
          if Lamp = slRed then
            D := IconDistance(Px, Py, 0, STANDING)
          else
            D := IconDistance(Px, Py, 5, WALKING);
          Icon := UnitValue(0.5 - D * Canvas.Scale);
        end;
        Lens := MixColor(ScaleColor(Lens, 0.63), ScaleColor(Hue, 0.33),
          Icon * (0.12 + 0.19 * Light.Day));
      end;

      if A.Optics = soLED then
      begin
        ColLED := Px - LED_PITCH * Round(Px / LED_PITCH);
        Dot := UnitValue(0.5 + (1.82 - Sqrt(Sqr(ColLED) + RowLED)) * Canvas.Scale);
        Pattern := 0.50 + Detail * (Dot - 0.50);
        Lens := ScaleColor(Lens, 0.78 + 0.55 * Pattern);
        if Lit then
        begin
          Emission := Icon * (0.21 + 0.79 * Pattern);
          Lens := MixColor(Lens, ScaleColor(MixColor(Hue, Hot, 0.62 * Sqr(Pattern)),
            Brightness), Emission);
        end;
      end
      else
      begin
        // 電球式はフレネルの稜線と中央から広がる光を連続的に描く。
        Pattern := 0.5 + 0.5 * Cos(2.55 * Sqrt(Sqr(Px) + Sqr(Py)));
        Pattern := 0.5 + (Pattern - 0.5) * SmoothUnit((Canvas.Scale - 0.36) / 0.40);
        Lens := ScaleColor(Lens, 0.86 + 0.27 * Pattern);
        if Lit then
        begin
          Emission := UnitValue(1 - Sqr(U + 0.10) * 0.45 - Sqr(V + 0.10) * 0.53);
          Lens := MixColor(Lens, ScaleColor(MixColor(Hue, Hot, 0.70 * Sqr(Emission)),
            Brightness * (0.60 + 0.40 * Emission + 0.11 * Pattern)), Icon);
        end;
      end;

      if A.ShowHood then
        Lens := ScaleColor(Lens, 1 - 0.13 * SmoothUnit((-V - 0.32) * 1.5));
      Canvas.Blend(X, Y, Lens, Coverage);
    end;
  end;
end;

function WaitColumnArea(Canvas: TSignalCanvas; CenterY: Double;
  Column: TSignalWaitColumn): TRect;
var
  X: Double;
begin
  X := WAIT_COLUMN_X[Column];
  Result := Canvas.PixelBounds(X - WAIT_COLUMN_HW, CenterY - WAIT_COLUMN_HH,
    X + WAIT_COLUMN_HW, CenterY + WAIT_COLUMN_HH);
end;

procedure DrawWaitColumn(Canvas: TSignalCanvas; CenterY: Double;
  const Light: TSignalLightLevel; Column: TSignalWaitColumn; OnTopLens: Boolean;
  Count: Integer);
var
  I: Integer;
  X, Y: Double;
  Top, Bottom, OnTop, OnBottom, OffTop, OffBottom: TSignalColor;
begin
  X := WAIT_COLUMN_X[Column];
  Canvas.RoundBox(X, CenterY, WAIT_COLUMN_HW, WAIT_COLUMN_HH, 3,
    SurfaceColor($2A2425, Light), SurfaceColor($18171A, Light));

  OnTop := ScaleColor(SignalColor(WAIT_LED_TOP_COLOR[OnTopLens]),
    1.04 + 0.16 * (1 - Light.Day));
  OnBottom := ScaleColor(SignalColor(WAIT_LED_BOTTOM_COLOR[OnTopLens]),
    1 + 0.18 * (1 - Light.Day));
  OffTop := SurfaceColor($513336, Light);
  OffBottom := SurfaceColor($2D2023, Light);
  // 下側から残り段数を点灯し、残り時間の減少に伴って上側から消す。
  for I := 0 to SIGNAL_WAIT_BARS - 1 do
  begin
    Y := CenterY + ((SIGNAL_WAIT_BARS - 1) * 0.5 - I) * WAIT_LED_PITCH;
    if I < Count then
    begin
      Top := OnTop;
      Bottom := OnBottom;
    end
    else
    begin
      Top := OffTop;
      Bottom := OffBottom;
    end;
    Canvas.RoundBox(X, Y, 2.9, 1.64, 1.25, Top, Bottom);
  end;
end;

procedure DrawHousing(Canvas: TSignalCanvas; const A: TSignalAppearance;
  const Layout: TSignalLayout; const Light: TSignalLightLevel);
var
  Body, Hood, LightMetal, DarkMetal: TSignalColor;
  HW, HH: Double;
  Lamp: TSignalLamp;
begin
  Body := SurfaceColor(A.BodyColor, Light);
  Hood := SurfaceColor(A.HoodColor, Light);
  LightMetal := MixColor(Body, SurfaceColor($E2E0D6, Light), 0.36);
  DarkMetal := ScaleColor(Body, 0.52);
  HW := Layout.BodyHW;
  HH := Layout.BodyHH;
  if A.PoleLength > 0 then
    DrawPole(Canvas, Layout.PoleX, HH - 1, A.PoleLength + 1,
      SurfaceColor(A.PoleColor, Light));

  Canvas.RoundBox(3.7, 4.3, HW + 1.5, HH + 0.6, 16,
    ScaleColor(Body, 0.71), ScaleColor(Body, 0.32));
  Canvas.RoundBox(0, 0, HW, HH, 15.5, LightMetal, DarkMetal);
  Canvas.RoundBox(0, -0.6, HW - 2.3, HH - 2.5, 13.7,
    ScaleColor(Body, 0.87), ScaleColor(Body, 0.63));
  Canvas.RoundBox(0, 0, HW - 5.1, HH - 5.1, 11.4,
    ScaleColor(Body, 1.07), ScaleColor(Body, 0.81));

  Fastener(Canvas, -HW + 11, -HH + 11, Body);
  Fastener(Canvas, HW - 11, -HH + 11, Body);
  Fastener(Canvas, -HW + 11, HH - 11, Body);
  Fastener(Canvas, HW - 11, HH - 11, Body);
  for Lamp := slRed to slYellow do
  begin
    if IsPedestrian(A.Kind) and (Lamp = slYellow) then Continue;
    DrawBezel(Canvas, A.Kind, Layout.Lamps[Lamp], Body, Hood, A.ShowHood);
    DrawLens(Canvas, A, Layout.Lamps[Lamp], Light, Lamp, False, SignalColor($FFFFFF));
  end;
end;

procedure DrawLitLamp(Canvas: TSignalCanvas; const A: TSignalAppearance;
  const Layout: TSignalLayout; const Light: TSignalLightLevel;
  Lamp: TSignalLamp; Tint: Cardinal);
var
  P: TPointF;
  Glow, Radius, Intensity: Double;
  Correction, Hue: TSignalColor;
begin
  P := Layout.Lamps[Lamp];
  Correction := SignalColor(Tint);
  Hue := TintColor(LampColor(Lamp), Correction);
  Intensity := Max(Hue.R, Max(Hue.G, Hue.B));
  Glow := 1 - Light.Day;
  Radius := 39 + 25 * Glow;
  if A.Optics = soLED then Radius := Radius - 4;
  if A.ShowHood then
    Canvas.Halo(P.X, P.Y + 2, Radius, Radius * 0.92, Hue,
      Intensity * (0.20 + 0.63 * Glow))
  else
    Canvas.Halo(P.X, P.Y, Radius, Radius, Hue,
      Intensity * (0.24 + 0.65 * Glow));
  DrawLens(Canvas, A, P, Light, Lamp, True, Correction);
end;

end.

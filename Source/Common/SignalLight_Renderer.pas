unit SignalLight_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// エフェクト単位で完成画像を再利用し、灯火と目盛りは部分領域だけ更新する。

interface

uses AviUtl2FilterTypes, SignalLight_Settings, SignalLight_Raster, SignalLight_Artwork;

type
  TSignalRenderer = class
  private
    FCanvas: TSignalCanvas;
    FAppearance: TSignalAppearance;
    FLayout: TSignalLayout;
    FLight: TSignalLightLevel;
    // 灯火の下には筐体、目盛りの下には現在の灯火を含む画像を退避する。
    FLampPatch: TSignalPatch;
    FWaitPatches: array[TSignalWaitColumn] of TSignalPatch;
    FLastLamp: TSignalLamp;
    FLastBars: Integer;
    FLastWaitOnTop: Boolean;
    FLastTint: Cardinal;
    FValid: Boolean;
    procedure Rebuild(const A: TSignalAppearance);
  public
    constructor Create;
    destructor Destroy; override;
    // 現在の設定を反映し、描画器所有のRGBAとサイズを返す。
    // 画素ポインターは次のRenderまたは破棄まで有効。借用中の並行呼び出しは呼出側で防ぐ。
    procedure Render(const A: TSignalAppearance; const Frame: TSignalFrame;
      Tint: Cardinal; out Pixels: PPIXEL_RGBA; out Width, Height: Integer);
  end;

implementation

uses System.Types;

constructor TSignalRenderer.Create;
begin
  inherited Create;
  FCanvas := TSignalCanvas.Create;
end;

destructor TSignalRenderer.Destroy;
begin
  FCanvas.Free;
  inherited;
end;

procedure TSignalRenderer.Rebuild(const A: TSignalAppearance);
var
  Column: TSignalWaitColumn;
begin
  FAppearance := A;
  FLayout := MakeLayout(A);
  FLight := SampleLight(A.Hour);
  FCanvas.Reset(FLayout.HalfWidth, FLayout.HalfHeight, A.Zoom / 100);
  DrawHousing(FCanvas, A, FLayout, FLight);
  FLastLamp := slNone;
  FLastBars := 0;
  FLampPatch := Default(TSignalPatch);
  for Column := Low(TSignalWaitColumn) to High(TSignalWaitColumn) do
    FWaitPatches[Column] := Default(TSignalPatch);
end;

procedure TSignalRenderer.Render(const A: TSignalAppearance; const Frame: TSignalFrame;
  Tint: Cardinal; out Pixels: PPIXEL_RGBA; out Width, Height: Integer);
var
  RebuildHousing, UpdateLamp, UpdateWait, RefreshWaitPatch: Boolean;
  WaitY: Double;
  Column: TSignalWaitColumn;
  P: TPointF;
begin
  RebuildHousing := not FValid or not A.SameAs(FAppearance);
  UpdateLamp := RebuildHousing or (Frame.Lamp <> FLastLamp) or
    ((Frame.Lamp <> slNone) and (Tint <> FLastTint));
  RefreshWaitPatch := UpdateLamp or (Frame.WaitOnTop <> FLastWaitOnTop);
  UpdateWait := (A.Kind = skPedestrianWait) and (RefreshWaitPatch or (Frame.WaitBars <> FLastBars));

  if UpdateLamp or UpdateWait then
  begin
    // 描画途中で例外が起きた場合は、次の呼び出しで筐体から再描画する。
    FValid := False;
    if RebuildHousing then
      Rebuild(A)
    else if UpdateWait then
      // グローと目盛りが重なるため、上に合成した目盛りから先に戻す。
      for Column := Low(TSignalWaitColumn) to High(TSignalWaitColumn) do
        FCanvas.RestorePatch(FWaitPatches[Column]);

    if UpdateLamp then
    begin
      // 2灯のグロー範囲が重なる場合も、先に前の灯火の領域を戻す。
      if FLastLamp <> slNone then
        FCanvas.RestorePatch(FLampPatch);
      if Frame.Lamp <> slNone then
      begin
        if Frame.Lamp <> FLastLamp then
        begin
          P := FLayout.Lamps[Frame.Lamp];
          FCanvas.SavePatch(FLampPatch, FCanvas.PixelBounds(
            P.X - LAMP_PATCH_RADIUS, P.Y - LAMP_PATCH_RADIUS,
            P.X + LAMP_PATCH_RADIUS, P.Y + LAMP_PATCH_RADIUS));
        end;
        DrawLitLamp(FCanvas, A, FLayout, FLight, Frame.Lamp, Tint);
      end;
      FLastLamp := Frame.Lamp;
      FLastTint := Tint;
    end;

    if UpdateWait then
    begin
      if Frame.WaitOnTop then
        WaitY := FLayout.Lamps[slRed].Y
      else
        WaitY := FLayout.Lamps[slGreen].Y;
      for Column := Low(TSignalWaitColumn) to High(TSignalWaitColumn) do
      begin
        if RefreshWaitPatch then
          FCanvas.SavePatch(FWaitPatches[Column], WaitColumnArea(FCanvas, WaitY, Column));
        DrawWaitColumn(FCanvas, WaitY, FLight, Column, Frame.WaitOnTop, Frame.WaitBars);
      end;
      FLastWaitOnTop := Frame.WaitOnTop;
      FLastBars := Frame.WaitBars;
    end;
    FValid := True;
  end;

  Width := FCanvas.Width;
  Height := FCanvas.Height;
  Pixels := FCanvas.PixelData;
end;

end.

unit SignalLight_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 設定値と純粋な時刻評価。再生順序やレンダラーの状態には依存しない。

interface

const
  SIGNAL_MIN_ZOOM = 25;
  SIGNAL_MAX_ZOOM = 600;
  SIGNAL_MAX_POLE = 350;
  SIGNAL_MAX_DURATION = 600;
  SIGNAL_MAX_OFFSET = 3600;
  SIGNAL_MIN_BLINK = 0.01;
  SIGNAL_MAX_BLINK = 60;
  SIGNAL_WAIT_BARS = 10;

type
  TSignalKind = (skHorizontal, skVertical, skPedestrian, skPedestrianWait);
  TSignalOptics = (soBulb, soLED);
  TSignalPhase = (spRed, spGreen, spYellow, spGreenBlink);
  TSignalLamp = (slNone, slRed, slGreen, slYellow);

  TSignalAppearance = record
    Kind: TSignalKind;
    Optics: TSignalOptics;
    Zoom, Hour, PoleLength: Double; // %, 24時間表記, 100%時の画素
    BodyColor, PoleColor, HoodColor: Cardinal; // $RRGGBB
    ShowHood: Boolean;
    function SameAs(const Other: TSignalAppearance): Boolean;
  end;

  TSignalTiming = record
    StartPhase: TSignalPhase;
    Duration: array[TSignalPhase] of Double;
    Offset, BlinkPeriod: Double; // 秒
    RepeatCycle: Boolean;
  end;

  TSignalFrame = record
    Lamp: TSignalLamp;
    WaitBars: Integer;
    WaitOnTop: Boolean; // 青点滅の消灯中も、現在区間を基準にする。
  end;

// 非有限な値を既定値に戻してからホスト項目の範囲に収める。
function BoundedValue(Value, LowValue, HighValue, DefaultValue: Double): Double;

// 歩行者用の2種類は同じシーケンスと人物マークを使う。
function IsPedestrian(Kind: TSignalKind): Boolean;

// オブジェクトの経過秒から現在の灯火を計算する。待ち時間付きでは残り目盛りも返す。
function EvaluateSignal(Kind: TSignalKind; const Timing: TSignalTiming;
  Elapsed: Double): TSignalFrame;

implementation

uses System.Math;

type
  TPhaseOrder = array[0..2] of TSignalPhase;

const
  // 十進の設定値の加減算による誤差を切替境界で吸収する。
  TIME_EPSILON = 1E-9;
  VEHICLE_PHASES: TPhaseOrder = (spRed, spGreen, spYellow);
  PEDESTRIAN_PHASES: TPhaseOrder = (spRed, spGreen, spGreenBlink);
  PHASE_LAMP: array[TSignalPhase] of TSignalLamp = (slRed, slGreen, slYellow, slGreen);

function TSignalAppearance.SameAs(const Other: TSignalAppearance): Boolean;
begin
  Result := (Kind = Other.Kind) and (Optics = Other.Optics) and
    (Zoom = Other.Zoom) and (Hour = Other.Hour) and (PoleLength = Other.PoleLength) and
    (BodyColor = Other.BodyColor) and (PoleColor = Other.PoleColor) and
    (HoodColor = Other.HoodColor) and (ShowHood = Other.ShowHood);
end;

function BoundedValue(Value, LowValue, HighValue, DefaultValue: Double): Double;
begin
  if IsNaN(Value) or IsInfinite(Value) then
    Exit(DefaultValue);
  Result := EnsureRange(Value, LowValue, HighValue);
end;

function IsPedestrian(Kind: TSignalKind): Boolean;
begin
  Result := Kind in [skPedestrian, skPedestrianWait];
end;

function CyclePosition(Time, Period: Double): Double;
begin
  Result := Time - Int(Time / Period) * Period;
  if Result < 0 then
    Result := Result + Period;
  if (Result < TIME_EPSILON) or (Period - Result < TIME_EPSILON) then
    Result := 0;
end;

function EvaluateSignal(Kind: TSignalKind; const Timing: TSignalTiming;
  Elapsed: Double): TSignalFrame;
var
  Phases: TPhaseOrder;
  StartPhase, Phase: TSignalPhase;
  StartIndex, I: Integer;
  Position, Cycle, Duration, BlinkPeriod: Double;
begin
  StartPhase := Timing.StartPhase;
  if IsPedestrian(Kind) then
  begin
    Phases := PEDESTRIAN_PHASES;
    if StartPhase = spYellow then
      StartPhase := spRed;
  end
  else
  begin
    Phases := VEHICLE_PHASES;
    if StartPhase = spGreenBlink then
      StartPhase := spGreen;
  end;

  // 周期の終了時と全区間が0秒のときは、設定された開始色で静止する。
  Result.Lamp := PHASE_LAMP[StartPhase];
  Result.WaitBars := 0;
  Result.WaitOnTop := StartPhase in [spGreen, spGreenBlink];
  Cycle := 0;
  StartIndex := 0;
  for I := Low(Phases) to High(Phases) do
  begin
    Cycle := Cycle + Timing.Duration[Phases[I]];
    if Phases[I] = StartPhase then
      StartIndex := I;
  end;
  if Cycle <= TIME_EPSILON then
    Exit;

  if IsNaN(Elapsed) or IsInfinite(Elapsed) then
    Elapsed := 0;
  Position := Elapsed + Timing.Offset;
  if Timing.RepeatCycle then
    Position := CyclePosition(Position, Cycle)
  else
  begin
    Position := Max(0.0, Position);
    if Position + TIME_EPSILON >= Cycle then
      Exit;
  end;

  for I := Low(Phases) to High(Phases) do
  begin
    Phase := Phases[(StartIndex + I) mod Length(Phases)];
    Duration := Timing.Duration[Phase];
    if (Duration > 0) and (Position + TIME_EPSILON < Duration) then
    begin
      Result.Lamp := PHASE_LAMP[Phase];
      if Phase = spGreenBlink then
      begin
        BlinkPeriod := Timing.BlinkPeriod;
        if CyclePosition(Position, BlinkPeriod) + TIME_EPSILON >= BlinkPeriod * 0.5 then
          Result.Lamp := slNone;
      end;
      if Kind = skPedestrianWait then
      begin
        Result.WaitOnTop := Phase in [spGreen, spGreenBlink];
        Result.WaitBars := EnsureRange(Ceil((1 - Position / Duration) *
          SIGNAL_WAIT_BARS - TIME_EPSILON), 1, SIGNAL_WAIT_BARS);
      end;
      Exit;
    end;
    Position := Max(0.0, Position - Duration);
  end;
end;

end.

unit SignalLight_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// AviUtl2のパラメータ登録と、コールバック中の設定値の読み取り。

interface

uses SignalLight_Settings;

// 設定項目の実体はDLLが保持する。テーブル初期化後に一度呼ぶ。
procedure RegisterSignalParameters;
// ホストが保持する項目から、検証済みの描画設定・時間設定と$RRGGBBの色補正を返す。
// 項目の現在値は変更しない。
procedure ReadSignalSettings(out Appearance: TSignalAppearance;
  out Timing: TSignalTiming; out LampTint: Cardinal);

implementation

uses AviUtl2FilterTypes, PluginFilterTable;

const
  // 既存の選択肢との対応を保つため、表示名を変えるときも並びと値を維持する。
  KINDS: array[0..4] of TFILTER_ITEM_SELECT_ITEM = (
    (Name: '車両用横型'; Value: Ord(skHorizontal)),
    (Name: '車両用縦型'; Value: Ord(skVertical)),
    (Name: '歩行者信号1'; Value: Ord(skPedestrian)),
    (Name: '歩行者信号2'; Value: Ord(skPedestrianWait)),
    (Name: nil; Value: 0));
  OPTICS: array[0..2] of TFILTER_ITEM_SELECT_ITEM = (
    (Name: '電球式'; Value: Ord(soBulb)),
    (Name: 'LED式'; Value: Ord(soLED)),
    (Name: nil; Value: 0));
  START_PHASES: array[0..4] of TFILTER_ITEM_SELECT_ITEM = (
    (Name: '赤'; Value: Ord(spRed)),
    (Name: '青'; Value: Ord(spGreen)),
    (Name: '黄'; Value: Ord(spYellow)),
    (Name: '青点滅'; Value: Ord(spGreenBlink)),
    (Name: nil; Value: 0));

var
  SignalKind, OpticsKind, StartPhase: TFILTER_ITEM_SELECT;
  Zoom, Hour, PoleLength, Offset, BlinkPeriod: TFILTER_ITEM_TRACK;
  Durations: array[TSignalPhase] of TFILTER_ITEM_TRACK;
  BodyColor, PoleColor, HoodColor, LampTintItem: TFILTER_ITEM_COLOR;
  ShowHood, ShowPole, RepeatCycle: TFILTER_ITEM_CHECK;
  AppearanceGroup, AccessoriesGroup, SequenceGroup: TFILTER_ITEM_GROUP;

procedure RegisterSignalParameters;
begin
  AddSelect(SignalKind, '種類', Ord(skHorizontal), @KINDS[0]);
  AddSelect(OpticsKind, '点灯方式', Ord(soBulb), @OPTICS[0]);
  AddTrack(Zoom, '専用拡大率 (%)', 100, SIGNAL_MIN_ZOOM, SIGNAL_MAX_ZOOM, 1);
  AddTrack(Hour, '時間帯', 12, 0, 24, 0.01);

  AddGroup(AppearanceGroup, '外観', 0);
  AddColor(BodyColor, '本体色', $7C, $80, $7E);
  AddColor(PoleColor, '支柱色', $88, $8A, $85);
  AddColor(HoodColor, 'フード色', $29, $2B, $26);
  AddColor(LampTintItem, '点灯色の補正', $FF, $FF, $FF);
  AddTrack(PoleLength, '支柱の長さ', 176, 0, SIGNAL_MAX_POLE, 1);

  AddGroup(AccessoriesGroup, '付属物', 0);
  AddCheck(ShowHood, '遮光フード', 1);
  AddCheck(ShowPole, '支柱', 1);

  AddGroup(SequenceGroup, 'シーケンス', 0);
  AddSelect(StartPhase, '初期信号状態', Ord(spRed), @START_PHASES[0]);
  AddTrack(Offset, '時間オフセット (秒)', 0, -SIGNAL_MAX_OFFSET, SIGNAL_MAX_OFFSET, 0.01);
  AddTrack(Durations[spRed], '赤点灯時間 (秒)', 3, 0, SIGNAL_MAX_DURATION, 0.01);
  AddTrack(Durations[spGreen], '青点灯時間 (秒)', 3, 0, SIGNAL_MAX_DURATION, 0.01);
  AddTrack(Durations[spYellow], '黄点灯時間 (秒)', 3, 0, SIGNAL_MAX_DURATION, 0.01);
  AddTrack(Durations[spGreenBlink], '青点滅時間 (秒)', 3, 0, SIGNAL_MAX_DURATION, 0.01);
  AddTrack(BlinkPeriod, '点滅周期 (秒)', 1, SIGNAL_MIN_BLINK, SIGNAL_MAX_BLINK, 0.01);
  AddCheck(RepeatCycle, 'シーケンス繰り返し', 1);
end;

function ColorCode(const Item: TFILTER_ITEM_COLOR): Cardinal;
begin
  Result := (Cardinal(Item.R) shl 16) or (Cardinal(Item.G) shl 8) or Item.B;
end;

procedure ReadSignalSettings(out Appearance: TSignalAppearance;
  out Timing: TSignalTiming; out LampTint: Cardinal);
var
  Phase: TSignalPhase;
begin
  Appearance.Kind := skHorizontal;
  if (SignalKind.Value >= Ord(Low(TSignalKind))) and
    (SignalKind.Value <= Ord(High(TSignalKind))) then
    Appearance.Kind := TSignalKind(SignalKind.Value);
  Appearance.Optics := soBulb;
  if OpticsKind.Value = Ord(soLED) then
    Appearance.Optics := soLED;
  Appearance.Zoom := BoundedValue(Zoom.Value, SIGNAL_MIN_ZOOM, SIGNAL_MAX_ZOOM, 100);
  Appearance.Hour := BoundedValue(Hour.Value, 0, 24, 12);
  if Appearance.Hour = 24 then
    Appearance.Hour := 0;
  Appearance.PoleLength := 0;
  if ShowPole.Value <> 0 then
    Appearance.PoleLength := BoundedValue(PoleLength.Value, 0, SIGNAL_MAX_POLE, 176);
  Appearance.BodyColor := ColorCode(BodyColor);
  Appearance.PoleColor := ColorCode(PoleColor);
  Appearance.HoodColor := ColorCode(HoodColor);
  Appearance.ShowHood := ShowHood.Value <> 0;
  LampTint := ColorCode(LampTintItem);

  Timing.StartPhase := spRed;
  if (StartPhase.Value >= Ord(Low(TSignalPhase))) and
    (StartPhase.Value <= Ord(High(TSignalPhase))) then
    Timing.StartPhase := TSignalPhase(StartPhase.Value);
  for Phase := Low(TSignalPhase) to High(TSignalPhase) do
    Timing.Duration[Phase] := BoundedValue(Durations[Phase].Value, 0, SIGNAL_MAX_DURATION, 3);
  Timing.Offset := BoundedValue(Offset.Value, -SIGNAL_MAX_OFFSET, SIGNAL_MAX_OFFSET, 0);
  Timing.BlinkPeriod := BoundedValue(BlinkPeriod.Value, SIGNAL_MIN_BLINK, SIGNAL_MAX_BLINK, 1);
  Timing.RepeatCycle := RepeatCycle.Value <> 0;
end;

end.

program SignalLight_Auf2Tests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 本番AUF2を読み込み、登録項目、時刻評価、画素の決定性を検査する。

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  System.SysUtils, System.Math, System.Hash, Winapi.Windows, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TItemHeader = record ItemType, Name: PWideChar end;
  PItemHeader = ^TItemHeader;
  PSelectItem = ^TFILTER_ITEM_SELECT_ITEM;
  PItems = ^TItems;
  TItems = array[0..99] of Pointer;
  TTestImage = record
    Width, Height: Integer;
    Data: TBytes;
  end;

var
  Plugin: PFILTER_PLUGIN_TABLE;
  Video: TFILTER_PROC_VIDEO;
  Obj: TOBJECT_INFO;
  Param: TOBJECT_IMAGE_PARAM;
  Image: TTestImage;
  ReadInput: Boolean;
  FirstSession, SecondSession: Pointer;
  ImageDirectory: string;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then
    raise Exception.Create(Message);
end;

procedure Capture(Data: PPIXEL_RGBA; W, H: Integer); cdecl;
begin
  if (Data = nil) or (W < 1) or (H < 1) or (W > 8192) or (H > 8192) then Exit;
  Image.Width := W;
  Image.Height := H;
  SetLength(Image.Data, W * H * SizeOf(TPIXEL_RGBA));
  Move(Data^, Image.Data[0], Length(Image.Data));
end;

procedure GetImageData(Data: PPIXEL_RGBA); cdecl;
begin
  ReadInput := True;
end;

function FindItem(const Name, ItemType: string): Pointer;
var
  I: Integer;
  Item: PItemHeader;
begin
  for I := 0 to 99 do
  begin
    Item := PItems(Plugin^.Items)^[I];
    if Item = nil then Break;
    if string(Item^.Name) = Name then
    begin
      Check(string(Item^.ItemType) = ItemType, 'Incorrect type for ' + Name);
      Exit(Item);
    end;
  end;
  raise Exception.Create('Missing item ' + Name);
end;

function Track(const Name: string): PFILTER_ITEM_TRACK;
begin
  Result := FindItem(Name, 'track');
end;

function Choice(const Name: string): PFILTER_ITEM_SELECT;
begin
  Result := FindItem(Name, 'select');
end;

function Toggle(const Name: string): PFILTER_ITEM_CHECK;
begin
  Result := FindItem(Name, 'check');
end;

function Pixel(X, Y: Integer): TPIXEL_RGBA;
begin
  X := X + Image.Width div 2;
  Y := Y + Image.Height div 2;
  Check((X >= 0) and (X < Image.Width) and (Y >= 0) and (Y < Image.Height),
    'Sample outside the generated image');
  Result := PPIXEL_RGBA(@Image.Data[(Y * Image.Width + X) * SizeOf(TPIXEL_RGBA)])^;
end;

procedure Render(Seconds: Double);
var
  PreviousParam: TOBJECT_IMAGE_PARAM;
begin
  Obj.Time := Seconds;
  PreviousParam := Param;
  Image.Width := 0;
  ReadInput := False;
  Check(Plugin^.Func_Proc_Video(@Video) = 1, 'Video callback failed at ' + FloatToStr(Seconds));
  Check(Image.Width > 0, 'Video callback did not submit an image');
  Check(not ReadInput, 'Media object read a host input image');
  Check(CompareMem(@PreviousParam, @Param, SizeOf(Param)), 'Host transform was changed');
end;

function Snapshot(Seconds: Double): string;
var Hash: THashSHA2;
begin
  Render(Seconds);
  Hash := THashSHA2.Create;
  Hash.Update(Image.Data);
  Result := IntToStr(Image.Width) + 'x' + IntToStr(Image.Height) + ' ' + Hash.HashAsString;
end;

procedure SaveFrame(const Name: string);
var
  PNG: TPngImage;
  X, Y: Integer;
  Row: PByte;
  P: PPIXEL_RGBA;
begin
  PNG := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, Image.Width, Image.Height);
  try
    for Y := 0 to Image.Height - 1 do
    begin
      Row := PNG.Scanline[Y];
      P := PPIXEL_RGBA(@Image.Data[Y * Image.Width * SizeOf(TPIXEL_RGBA)]);
      for X := 0 to Image.Width - 1 do
      begin
        Row[3 * X] := P^.B;
        Row[3 * X + 1] := P^.G;
        Row[3 * X + 2] := P^.R;
        PNG.AlphaScanline[Y]^[X] := P^.A;
        Inc(P);
      end;
    end;
    PNG.SaveToFile(ImageDirectory + Name + '.png');
  finally
    PNG.Free;
  end;
end;

procedure CheckWaitBars(OnTopLens: Boolean; Expected: Integer);
const
  COLUMNS: array[0..1] of Integer = (-27, 26);
var
  X, Y, CenterY, I: Integer;
  P: TPIXEL_RGBA;
  Lit: Boolean;
begin
  if OnTopLens then
    CenterY := -42
  else
    CenterY := 42;
  for X in COLUMNS do
    for I := 0 to 9 do
    begin
      Y := Round(CenterY + (4.5 - I) * 4.85 - 0.5);
      P := Pixel(X, Y);
      if OnTopLens then
        Lit := (P.G > 130) and (P.G > P.R + 70) and (P.B > 110)
      else
        Lit := (P.R > 145) and (P.R > P.G + 75);
      Check(Lit = (I < Expected), Format('Countdown mismatch at pixel (%d, %d)', [X, Y]));
    end;
end;

procedure CheckRegistration;
const
  KINDS: array[0..3] of string = (
    '車両用横型', '車両用縦型', '歩行者信号1', '歩行者信号2');
  DURATIONS: array[0..3] of string = (
    '赤点灯時間 (秒)', '青点灯時間 (秒)', '黄点灯時間 (秒)', '青点滅時間 (秒)');
var
  GroupIndex, I: Integer;
  Item: PItemHeader;
  Option: PSelectItem;
  Name: string;
begin
  Check(Plugin <> nil, 'Missing filter table');
  Check(Plugin^.Flag = FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
    'Incorrect media object flags');
  Check((string(Plugin^.Name) = '交通信号') and (string(Plugin^.Label_) = 'SYNC'),
    'Incorrect registration name or label');
  Check(Assigned(Plugin^.Func_Create) and Assigned(Plugin^.Func_Destroy) and
    Assigned(Plugin^.Func_Proc_Video) and not Assigned(Plugin^.Func_Proc_Audio),
    'Incorrect callbacks');
  GroupIndex := -1;
  for I := 0 to 21 do
  begin
    Item := PItems(Plugin^.Items)^[I];
    Check(Item <> nil, 'Premature end of parameter table');
    Check(string(Item^.Name) <> '待ち時間表示器', 'Legacy countdown checkbox is still visible');
    if string(Item^.ItemType) = 'group' then
      GroupIndex := I;
    case I of
      5..9: Check(GroupIndex = 4, 'Appearance group mismatch');
      11..12: Check(GroupIndex = 10, 'Accessories group mismatch');
      14..21: Check(GroupIndex = 13, 'Sequence group mismatch');
    end;
  end;
  Check(PItems(Plugin^.Items)^[22] = nil, 'Parameter table not terminated');
  Check(Choice('種類')^.Value = 0, 'Incorrect default signal');
  Option := PSelectItem(Choice('種類')^.List);
  for I := Low(KINDS) to High(KINDS) do
  begin
    Check((string(Option^.Name) = KINDS[I]) and (Option^.Value = I),
      'Incorrect signal kind ' + KINDS[I]);
    Inc(Option);
  end;
  Check(Option^.Name = nil, 'Signal kind list not terminated');
  Check(Choice('初期信号状態')^.Value = 0, 'Incorrect initial phase');
  Check(Track('専用拡大率 (%)')^.Value = 100, 'Incorrect default zoom');
  with Track('時間帯')^ do
    Check((Value = 12) and (S = 0) and (E = 24) and SameValue(Step, 0.01),
      'Incorrect time of day track');
  for Name in DURATIONS do
    with Track(Name)^ do
      Check((Value = 3) and (S = 0) and SameValue(Step, 0.01), 'Incorrect duration ' + Name);
  Check((Track('時間オフセット (秒)')^.Value = 0) and (Track('点滅周期 (秒)')^.Value = 1),
    'Incorrect offset or blink period defaults');
  Check((Toggle('遮光フード')^.Value = 1) and (Toggle('支柱')^.Value = 1) and
    (Toggle('シーケンス繰り返し')^.Value = 1),
    'Incorrect checkbox defaults');
end;

procedure CheckSequenceAndDrawing;
var
  Red, Green, Yellow, Initial, BlinkOn, BlinkOff, Other, Night, Noon, Bare: string;
  StandardPedestrian, NightWaitGreen: string;
  ColorItem: PFILTER_ITEM_COLOR;
  OriginalWidth, OriginalHeight: Integer;
  P: TPIXEL_RGBA;
begin
  Red := Snapshot(0);
  P := Pixel(92, 0);
  Check((P.A = 255) and (P.R > P.G + 55) and (Pixel(-92, 0).G < 100),
    'Horizontal default red lamp missing or misplaced');
  Check(Pixel(0, -85).A = 0, 'Default object background should be transparent');
  Check((Pixel(-122, 95).A = 255) and (Pixel(0, 95).A = 0),
    'Horizontal pole must be on the left');
  SaveFrame('01-horizontal-bulb-noon');
  Green := Snapshot(3);
  P := Pixel(-92, 0);
  Check((P.G > P.R + 45) and (Pixel(92, 0).R < 100), 'Horizontal green lamp misplaced');
  Yellow := Snapshot(6);
  P := Pixel(0, 0);
  Check((P.R > 200) and (P.G > 120) and (P.B < P.G - 55), 'Yellow lamp misplaced');
  Check((Snapshot(9) = Red) and (Snapshot(5.999) = Green) and
    (Snapshot(2.999) = Red) and (Snapshot(7) = Yellow), 'Vehicle boundaries or reverse seek');
  Track('時間オフセット (秒)')^.Value := 2;
  Check((Snapshot(0.999) = Red) and (Snapshot(1) = Green), 'Partial-phase offset');
  Track('時間オフセット (秒)')^.Value := 8;
  Check((Snapshot(0) = Yellow) and (Snapshot(1) = Red), 'Multi-phase offset');
  Track('時間オフセット (秒)')^.Value := -1;
  Check(Snapshot(0) = Yellow, 'Negative repeat offset');
  Track('時間オフセット (秒)')^.Value := 0;

  Choice('初期信号状態')^.Value := 1;
  Toggle('シーケンス繰り返し')^.Value := 0;
  Check((Snapshot(0) = Green) and (Snapshot(3) = Yellow) and
    (Snapshot(6) = Red) and (Snapshot(9) = Green) and (Snapshot(100) = Green),
    'Nonrepeat cycle from green');
  Track('青点灯時間 (秒)')^.Value := 0;
  Check((Snapshot(0) = Yellow) and (Snapshot(3) = Red) and (Snapshot(6) = Green),
    'Zero durations or stopped initial state');
  Track('赤点灯時間 (秒)')^.Value := 0;
  Track('黄点灯時間 (秒)')^.Value := 0;
  Check(Snapshot(100) = Green, 'All zero durations should hold initial lamp');
  Track('赤点灯時間 (秒)')^.Value := 0.1;
  Track('青点灯時間 (秒)')^.Value := 0.2;
  Track('黄点灯時間 (秒)')^.Value := 0.3;
  Choice('初期信号状態')^.Value := 0;
  Check((Snapshot(0.1) = Green) and (Snapshot(0.3) = Yellow), 'Decimal boundary error');
  Track('赤点灯時間 (秒)')^.Value := 3;
  Track('青点灯時間 (秒)')^.Value := 3;
  Track('黄点灯時間 (秒)')^.Value := 3;
  Toggle('シーケンス繰り返し')^.Value := 1;

  Track('時間帯')^.Value := 0;
  Night := Snapshot(0);
  Check((Night <> Red) and (Pixel(92, 56).A > 0), 'Night halo missing');
  SaveFrame('04-horizontal-bulb-night');
  Track('時間帯')^.Value := 24;
  Check(Snapshot(0) = Night, 'Midnight endpoint mismatch');
  Track('時間帯')^.Value := 12;
  Noon := Snapshot(0);
  Check((Noon = Red) and (Pixel(92, 56).A = 0), 'Noon restore or excess halo');
  Track('時間帯')^.Value := 6;
  Check((Snapshot(0) <> Noon) and (Snapshot(0) <> Night), 'Dawn lighting missing');

  Track('時間帯')^.Value := 12;
  Toggle('遮光フード')^.Value := 0;
  Bare := Snapshot(0);
  Check(Bare <> Red, 'Visor checkbox did not affect drawing');
  Toggle('支柱')^.Value := 0;
  Check((Snapshot(0) <> Bare) and (Pixel(92, 0).R > 170), 'Support checkbox or centering');
  Toggle('遮光フード')^.Value := 1;
  Toggle('支柱')^.Value := 1;

  Choice('種類')^.Value := 1;
  Choice('点灯方式')^.Value := 1;
  Track('時間帯')^.Value := 18;
  Check(Snapshot(0) <> Red, 'Vertical LED design missing');
  P := Pixel(0, -85);
  Check((P.R > 190) and (P.R > P.G + 30) and (Pixel(0, 85).G < 100),
    'Vertical red lamp misplaced');
  Render(3);
  P := Pixel(0, 85);
  Check(P.G > P.R + 25, 'Vertical green lamp misplaced');
  Check((Pixel(0, 172).A = 255) and (Pixel(-25, 172).A = 0),
    'Vertical pole must stay centered');
  SaveFrame('02-vertical-led-dusk');
  Check(Snapshot(3) = Snapshot(4.8), 'Vertical signal rendered a countdown');

  Choice('種類')^.Value := 2;
  Track('時間帯')^.Value := 12;
  StandardPedestrian := Snapshot(0);
  Check(Pixel(0, -42).R > Pixel(0, 42).R + 30, 'Pedestrian standing mark missing');
  Check((Pixel(0, 160).A = 255) and (Pixel(-25, 160).A = 0),
    'Pedestrian pole must stay centered');
  CheckWaitBars(False, 0);
  CheckWaitBars(True, 0);
  SaveFrame('07-pedestrian-led-standard');
  Check(Snapshot(1.5) = StandardPedestrian, 'Standard pedestrian signal rendered a countdown');
  Render(3.9);
  Check(Pixel(5, 22).G > 70, 'Standard pedestrian walking mark missing');
  Render(6.5);
  Check(Pixel(5, 22).G < 70, 'Standard pedestrian blinking state was lost');

  Choice('種類')^.Value := 3;
  Initial := Snapshot(0);
  Check(Initial <> StandardPedestrian, 'Countdown variant is identical to the standard signal');
  CheckWaitBars(False, 10);
  CheckWaitBars(True, 0);
  Check((Pixel(0, -42).R > Pixel(0, 42).R + 30) and (Pixel(-25, 133).A = 0),
    'Countdown must be integrated into the lower lamp');
  SaveFrame('03-pedestrian-led-stop');
  Render(1.5);
  CheckWaitBars(False, 5);
  SaveFrame('08-pedestrian-led-mid-countdown');
  Render(3);
  CheckWaitBars(False, 0);
  CheckWaitBars(True, 10);
  Render(3.9);
  Check(Pixel(5, 22).G > 70, 'Countdown pedestrian walking mark missing');
  CheckWaitBars(False, 0);
  CheckWaitBars(True, 7);
  SaveFrame('06-pedestrian-led-walk');
  BlinkOn := Snapshot(6);
  CheckWaitBars(True, 10);
  BlinkOff := Snapshot(6.5);
  CheckWaitBars(False, 0);
  CheckWaitBars(True, 9);
  SaveFrame('09-pedestrian-led-blink-off');
  Check((BlinkOn <> BlinkOff) and (Pixel(5, 22).G < 70), 'Pedestrian blink off failure');
  Check((Snapshot(6.2) = BlinkOn) and (Snapshot(8.5) <> Initial) and
    (Snapshot(9) = Initial) and (Snapshot(6.5) = BlinkOff), 'Pedestrian seek or blink timing');

  // 逆順や別インスタンスを挟んだ描画を、同条件の新しいキャッシュと比較する。
  Toggle('シーケンス繰り返し')^.Value := 0;
  Render(9);
  CheckWaitBars(False, 0);
  CheckWaitBars(True, 0);
  Toggle('シーケンス繰り返し')^.Value := 1;
  Video.UserData := SecondSession;
  Check(Snapshot(6.5) = BlinkOff, 'Fresh session mismatch');
  Track('時間帯')^.Value := 0;
  NightWaitGreen := Snapshot(3.9);
  Render(8.6);
  Render(0.15);
  Check(Snapshot(3.9) = NightWaitGreen, 'Countdown and lamp glow overlap after seeking');
  Choice('種類')^.Value := 0;
  Track('時間帯')^.Value := 18;
  Track('支柱の長さ')^.Value := 90;
  Other := Snapshot(3);
  SaveFrame('05-horizontal-led-dusk');
  ColorItem := FindItem('点灯色の補正', 'color');
  ColorItem^.G := 127;
  Check((Snapshot(3) <> Other) and (Snapshot(3) <> Red), 'Lamp tint was not applied');
  ColorItem^.G := 255;
  Check(Snapshot(3) = Other, 'Lamp patch changed after tint reversal');

  Video.UserData := FirstSession;
  Choice('種類')^.Value := 3;
  Track('時間帯')^.Value := 12;
  Track('支柱の長さ')^.Value := 176;
  Check((Snapshot(6.5) = BlinkOff) and (Snapshot(0) = Initial), 'Per-object cache was mixed');

  Choice('種類')^.Value := 0;
  Track('支柱の長さ')^.Value := 350;
  Render(0);
  OriginalWidth := Image.Width;
  OriginalHeight := Image.Height;
  Track('専用拡大率 (%)')^.Value := 600;
  Render(0);
  Check((Image.Width = OriginalWidth * 6) and (Image.Height = OriginalHeight * 6),
    'Maximum zoom output is not rendered to size');
  Track('専用拡大率 (%)')^.Value := 25;
  Render(6);
  Check(Image.Width = OriginalWidth div 4, 'Minimum zoom output is not rendered to size');
  Track('専用拡大率 (%)')^.Value := NaN;
  Render(0);
  Check(Image.Width = OriginalWidth, 'Invalid zoom was not sanitized');
end;

procedure Run;
var
  Module: HMODULE;
  Initialize: TInitialize;
  Required: TRequired;
  Uninitialize: TUninitialize;
  GetTable: TGetTable;
begin
  Check(ParamCount = 2, 'Usage: SignalLight_Auf2Tests <AUF2 path> <PNG directory>');
  ImageDirectory := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  ForceDirectories(ImageDirectory);
  Module := LoadLibrary(PChar(ExpandFileName(ParamStr(1))));
  Check(Module <> 0, 'AUF2 failed to load');
  try
    Initialize := TInitialize(GetProcAddress(Module, 'InitializePlugin'));
    Required := TRequired(GetProcAddress(Module, 'RequiredVersion'));
    Uninitialize := TUninitialize(GetProcAddress(Module, 'UninitializePlugin'));
    GetTable := TGetTable(GetProcAddress(Module, 'GetFilterPluginTable'));
    Check(Assigned(Initialize) and Assigned(Required) and Assigned(Uninitialize) and
      Assigned(GetTable), 'Missing exports');
    Check(Required() = 2011600, 'Incorrect version requirement');
    Check(Initialize(Required() - 1) = 0, 'Unsupported host accepted');
    Check(Initialize(Required()) = 1, 'Initialization failed');
    try
      Plugin := GetTable();
      CheckRegistration;
      FirstSession := Plugin^.Func_Create(1);
      SecondSession := Plugin^.Func_Create(2);
      try
        Check((FirstSession <> nil) and (SecondSession <> nil) and
          (FirstSession <> SecondSession), 'Session creation failed');
        Video.Object_ := @Obj;
        Video.Param := @Param;
        Video.GetImageData := GetImageData;
        Video.SetImageData := Capture;
        Video.UserData := FirstSession;
        Param.X := 120;
        Param.RZ := 12;
        Param.Alpha := 0.63;
        CheckSequenceAndDrawing;
      finally
        Plugin^.Func_Destroy(2, SecondSession);
        Plugin^.Func_Destroy(1, FirstSession);
      end;
    finally
      Uninitialize;
    end;
  finally
    FreeLibrary(Module);
  end;
  Writeln('PASS: AUF2 registration, rendering, sequencing, zoom and per-instance caches');
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FAIL: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

unit SYNC_SignalLight_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 交通信号をメディアオブジェクトとして登録し、透過画像をホストへ返す。

interface

uses AviUtl2FilterTypes;

const
  SIGNALLIGHT_REQUIRED_VERSION = 2011600;

// DLL所有の登録テーブルを返す。呼出側で解放しない。
function GetSignalLightFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows, PluginFilterTable,
  SignalLight_Settings, SignalLight_Parameters, SignalLight_Renderer;

type
  TSignalSession = class
    Lock: TCriticalSection;
    Renderer: TSignalRenderer;
    constructor Create;
    destructor Destroy; override;
  end;

var
  TableInitialized: Boolean;

constructor TSignalSession.Create;
begin
  inherited Create;
  Lock := TCriticalSection.Create;
  Renderer := TSignalRenderer.Create;
end;

destructor TSignalSession.Destroy;
begin
  Renderer.Free;
  Lock.Free;
  inherited;
end;

// 透明な初期画像を生成する。ホストの標準パラメータはホストに任せる。
function SignalVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Session: TSignalSession;
  Appearance: TSignalAppearance;
  Timing: TSignalTiming;
  Frame: TSignalFrame;
  Pixels: PPIXEL_RGBA;
  Width, Height: Integer;
  Tint: Cardinal;
begin
  Result := 0;
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) or
    not Assigned(Video^.SetImageData) then Exit;
  try
    ReadSignalSettings(Appearance, Timing, Tint);
    Frame := EvaluateSignal(Appearance.Kind, Timing, Video^.Object_^.Time);
    Session := TSignalSession(Video^.UserData);
    Session.Lock.Acquire;
    try
      Session.Renderer.Render(Appearance, Frame, Tint, Pixels, Width, Height);
      Video^.SetImageData(Pixels, Width, Height);
      Result := 1;
    finally
      Session.Lock.Release;
    end;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_SignalLight video: ' + E.Message));
  end;
end;

// ホストが作成するエフェクトインスタンスと同じ寿命で描画資源を保持する。
function CreateSignal(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TSignalSession.Create;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_SignalLight create: ' + E.Message));
  end;
end;

procedure DestroySignal(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TSignalSession(UserData).Free;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_SignalLight destroy: ' + E.Message));
  end;
end;

function GetSignalLightFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      '交通信号', 'SYNC', '交通信号 / SYNC_SignalLight v1.0.0', SignalVideo, nil);
    RegisterSignalParameters;
    GetPluginTable^.Func_Create := CreateSignal;
    GetPluginTable^.Func_Destroy := DestroySignal;
    TableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.

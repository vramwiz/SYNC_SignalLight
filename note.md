# SYNC_SignalLight 作業ノート

- 交通信号を「SYNC」グループのメディアオブジェクトとして登録する。作業フォルダーは D:\DelphiProg\MyApp\SYNC_SignalLight。参考元は D:\DelphiProg\MyApp\SYNC_WeatherFX。
- 本番は SYNC_SignalLight.dproj と SYNC_SignalLight.auf2。機能と設定は [README.md](README.md) に記載する。

## ビルド

Delphi 37.0 / Win64。IDE では SYNC_SignalLight.dproj を直接開く。プロジェクトルートで rsvars.bat を呼び、MSBuild で Debug / Release の両方を実行する。最後に Release を配置する。

~~~powershell
New-Item -ItemType Directory -Force -Path Win64\BuildLogs | Out-Null
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_SignalLight.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /fl /flp:"logfile=Win64\BuildLogs\Debug.log;verbosity=normal;encoding=UTF-8"'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_SignalLight.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /fl /flp:"logfile=Win64\BuildLogs\Release.log;verbosity=normal;encoding=UTF-8"'
~~~

- 両構成の出力先は C:\ProgramData\aviutl2\Plugin\SYNC_SignalLight\。ビルド後イベントは DLL を AUF2 へコピーし、成功後に DLL を削除する。Release では RSM も削除する。デバッガーホストは参考元と同じ D:\aviutl2_v2.1.16\aviutl2.exe。
- DCU は Win64\Debug\DCU と Win64\Release\DCU。ユニット追加時は .dpr の in と .dproj の DCCReference を両方更新し、必要に応じて検索パスを登録する。
- MSBuild の検査結果と IDE 内の表示確認は区別する。通常のビルド・検査はコマンドラインで行う。

## ソース配置と共通規則

- SYNC_SignalLight.dpr は公開関数と最低対応バージョン、Source/Plugin/Filter は登録・項目の読み取り・ホストへの画像転送を担当する。
- Source/Common はシーケンス評価、RGBA 描画、灯器の形状、描画キャッシュを担当する。画像の中心は灯器の中心。横型の支柱は左側、縦型と歩行者用の支柱は中央に取り付ける。
- 描画器はエフェクトごとに完成画像と灯火・目盛りの部分領域を保持する。「歩行者信号2」は赤のときに下段の左右に赤、青と青点滅のときに上段の左右に青の目盛りを表示する。描画時は目盛りの下を先に復元し、灯火・グローと目盛りを重ね直す。透過画像の最大寸法は 1920×4860（横型、支柱の長さ 350、拡大率 600%）。別の構成では縦方向の最大寸法が 5952 になる。
- ユニット先頭に目的と責務を書く。公開処理には入出力、重要な副作用、必要に応じて所有権を書く。日本語を含む .pas / .dpr / .ps1 は UTF-8 BOM 付き、CRLF。約1,500行を目安に責務で分割する。
- SDK の型順序・サイズ・配置を変更する場合は公式定義と照合する。ホスト所有ポインターはコールバックの間だけ借り、DLL 境界で例外を捕捉する。
- setup は参考元から ZIP を含む 5 ファイルをそのままコピーした。カタログ、バッチ、ZIP は WeatherFX 用。配布先の変更や配布処理は別途行う。

## 検査

Tests/SignalLight_Auf2Tests.dpr は本番 AUF2 をロードし、登録項目と描画コールバックを検査する。次のコマンドは配置済みの AUF2 を検査し、Win64\Verification\Images に透過 PNG を出力する。Debug を指定する場合は、Release ビルドの前に退避した AUF2 を -PluginPath で渡す。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\run_tests.ps1
~~~

2026-11-27 に Win64 Debug / Release を再ビルドし、両方で警告0・エラー0を確認。4種類の登録、赤・青それぞれの目盛りの位置と色、青点滅中の残り目盛り、逆順シークとグローとの重なりを本番 AUF2 で検査した。表示名を「歩行者信号1」「歩行者信号2」に変更し、登録名と選択値を検査した。出力 PNG 9 枚は両構成で一致し、改名前の Release とも一致した。AviUtl2 と Delphi IDE の画面上の確認は未実施。

- ビルドログは Win64\BuildLogs、検査ログと画像は Win64\Verification\SignalKindNames。
- 配置済み Release の SHA-256 は 983F6774F6BEB8CC13DA2ACDB3E7E745D5BAB72FEFF66A7B6810AA74B9504019。
- setup の全5ファイルと SDK・登録ユニット・ライセンスのコピーは SHA-256 が参考元と一致した。

# SYNC_SignalLight の配布ファイル作成

make_release_zip.bat は、既存の SYNC_SignalLight.auf2 から SYNC_SignalLight.zip を作成し、SYNC_SignalLight.catalog.json の最終バージョンに本体の XXH3-128 を設定します。初回の配布タグは v1.0.0 です。

標準の参照先は C:\ProgramData\aviutl2\Plugin\SYNC_SignalLight です。xxhsum.exe は Win64\Dependencies\xxHash-0.8.4 に配置するか、PATH へ登録します。[xxHash v0.8.4 Windows 版](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)

~~~bat
setup\make_release_zip.bat
~~~

配置先やハッシュ計算ツールのパスを指定できます。

~~~bat
setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_SignalLight" -XxhsumPath "D:\Tools\xxhsum.exe"
~~~

ZIP には SYNC_SignalLight フォルダーが入り、本体、README、ライセンス、SDK のライセンス表示を同梱します。カタログはこのフォルダーを Plugin 配下に配置し、アンインストール時には同じ製品専用フォルダーを削除します。

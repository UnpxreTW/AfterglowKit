# AfterglowKit

Afterglow（跨 Apple 平台原生 PTT client）的引擎套件。
支援 iOS / iPadOS 17+、macOS 15+。

## 套件結構

| Target | 角色 |
|---|---|
| `PTTBig5Codec` | Big5-UAO codec：解碼表 + loader + ESC-aware 串流轉碼器（零外部 dep）|
| `afterglowdata` | dev-time 資料 / 表產生器（executable）|

## 開發

```sh
swift build
swift test
```

### 重新產生 UAO 對照表

對照表（`Sources/PTTBig5Codec/Generated/UAOTable.swift`）已產生並提交；consumer build 永不連網重生。
原始表不隨 repo 散布——重新產生時，產生器自 MozTW 官方 repo 的 commit-pinned URL 下載
b2u 原始表並驗證 SHA-256（不符即 hard-fail）；離線環境可將表放到套件根目錄
`uao250-b2u.txt` 作本機 override（同樣驗 SHA）。於套件根目錄執行：

```sh
swift run afterglowdata generate
```

產生器會在寫檔前自行驗證滿格、全表 round-trip 與 spot-check，任一不符即 hard-fail、不寫檔。

## 授權

本專案原始碼採 Apache-2.0（見 [LICENSE](LICENSE)）。
UAO 對照資料的出處與授權說明見 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

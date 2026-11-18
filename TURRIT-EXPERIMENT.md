# Turrit 聊天與分享實驗

以 Turrit 1.5.5（10387）為宿主。沿用 Turrit 的對話列表、帳號、通知註冊、點通知導覽、輸入列與發送。原先的 VoiceOver 補丁會在開啟對話時自動跳到最新訊息，這個分支交由 Turrit 決定進入位置。「跳到最新訊息」仍可手動使用。

在私訊、群組或頻道的訊息上，用 VoiceOver 動作「用訊息列表閱讀」打開 UIKit 列表。起始焦點是選取的訊息。列表呈現開啟當下這一頁的內容。「返回對話」或雙指 Z 字回到 Turrit，即可回覆或翻頁。底部頁籤和其餘彈窗目前沿用原有 Turrit 無障礙補丁。

## OC 打包

在 macOS 的本分支工作目錄執行以下指令。第二個輸入 IPA 請用此分支 NativeTelegram 目錄依既有流程編出的穩定版，含分享端原有的 API 設定。

```bash
bash scripts/build.sh
python3 scripts/package.py Turrit_1.5.5_78c.ipa build/AccessiGram.dylib Turrit-AccessiGram-experiment.ipa --native-ipa NativeTelegram/dist/AccessiGramNative-unsigned.ipa
```

輸出是待簽 IPA，主 App 保留 Turrit 的 Bundle ID，兩個通知 extension 沿用底包。打包器只替換分享 extension 的內容，使用 Turrit 原先的分享 Bundle ID。分享端使用 Accessi Gram 的獨立登入，首次分享可能需要登入一次。簽名時請沿用原本能收到推播的 Turrit 設定，相同的最終 Bundle ID 會覆蓋現有 Turrit。實機重點是鎖屏收到私訊後，點通知能否打開正確對話並回覆。

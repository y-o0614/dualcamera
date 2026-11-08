# Dual Camera 無料実機テスト版

iPhoneの内カメラと外カメラを同時にプレビューし、シャッター1回で前後のJPEGと時刻情報を保存します。WindowsからGitHub Actions上のMacでコンパイルし、Sideloadlyで手元のiPhoneに入れられるようにしたSwiftプロジェクトです。ExpoやEASは不要です。

## 用意するもの

- Windows、Git for Windows、GitHubアカウント
- iOS 16.4以降で、前後のカメラを同時使用できるiPhoneとUSBケーブル
- 無料のAppleアカウント。個人のiPhoneで動作を確認するために使います。
- [SideloadlyのWindows版](https://sideloadly.io/)。必要なiTunesとiCloudは、Sideloadly公式ページのWindows向け案内に従ってAppleのWeb配布版を使用します。

## 1. GitHubにソースを置く

GitHubで空のリポジトリを作ります。`README`、`.gitignore`、ライセンスの自動追加はオフのまま作成します。

- **Private**なら自分だけが見られます。GitHub Actionsの無料枠内で実行し、必要に応じてGitHubの請求設定で追加使用を止める予算を設定します。
- **Public**ならソースを誰でも閲覧できます。標準GitHub-hosted runnerの利用は無料です。このスターターのソースだけを対象にします。

ZIPを展開し、`DualCamera.xcodeproj`が見える階層でPowerShellを開きます。`.github/workflows/build-ios.yml`も同じ階層に含まれています。以下のURLを自分のリポジトリのHTTPS URLに置き換えて実行します。

```powershell
git init -b main
git add --all
git commit -m "Add Dual Camera app"
git remote add origin https://github.com/YOUR-NAME/dual-camera-free.git
git push -u origin main
```

`git commit`が名前やメールの設定を求めたときは、`git config user.name "表示名"`と`git config user.email "自分のGitHub用メールアドレス"`をこのフォルダーで実行してからやり直します。公開リポジトリでメールを隠したい場合は、GitHubが案内する`noreply`アドレスを使用できます。

## 2. IPAを作る

1. GitHubのリポジトリで **Actions → Build iPhone IPA → Run workflow** を選びます。ブランチは`main`を指定します。
2. 緑のチェックが出た実行結果を開き、**Artifacts → DualCamera-unsigned**をダウンロードします。
3. ダウンロードしたZIPを展開し、中の`DualCamera.ipa`を使います。ビルドはGitHub上で行い、署名は次の手順で自分のWindows上で行います。Appleアカウントの入力はGitHub上では不要です。

## 3. 自分のiPhoneに入れる

1. iPhoneをUSBでWindowsに接続し、ロックを解除します。「このコンピュータを信頼しますか？」が出たら許可します。
2. Sideloadlyを起動し、対象のiPhoneを選択します。`DualCamera.ipa`をウィンドウにドロップします。
3. 無料のAppleアカウントを入力し、`Start`を押して画面の認証案内に従います。初回はインストールを完了させてからiPhoneの設定を確認します。
4. デベロッパモードを求められたら、iPhoneの **設定 → プライバシーとセキュリティ → デベロッパモード** をオンにして再起動し、再起動後の確認を承認します。開発元を信頼するよう求められた場合は、**設定 → 一般 → VPNとデバイス管理** で自分のアカウントを選びます。
5. ホーム画面の`Dual Camera`を開き、カメラへのアクセスを許可します。

無料署名の有効期間は7日です。期限を更新するには、同じAppleアカウントとBundle IDのまま、同じIPAを上書きインストールします。コードを変更したときはGitHub上でビルドし直します。

## 撮影と確認

「前後の画像を保存」を押します。撮影ペアは、ファイルアプリの **このiPhone内 → Dual Camera → Captures** にあります。1回につき `front.jpg`、`rear.jpg`、`capture.json` の3ファイルを保存します。保存したペアのフレーム提示時刻の差を画面とJSONで確認できます。

最初にレンズを片方ずつ覆い、二つの映像が別のカメラから来ていることを確認します。続けて何回か撮影し、毎回2枚そろうか確認します。

## Macを借りられる場合

`DualCamera.xcodeproj`をXcodeで開き、iPhoneをMacに接続します。ターゲットの **Signing & Capabilities → Team** で無料の **Personal Team** を選び、実行先をiPhoneにして`Run`を押します。Bundle IDの重複が表示された場合は、`DualCamera/App.xcconfig`の`PRODUCT_BUNDLE_IDENTIFIER`を固有の値に変えます。Personal Teamでの署名も7日で期限が切れます。

## 公式資料

- [AppleのPersonal Team](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [Appleのデベロッパモード](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [GitHub Actionsの利用料金](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [GitHub Actionsの手動実行](https://docs.github.com/actions/managing-workflow-runs/manually-running-a-workflow)
- [SideloadlyのWindows向け要件とFAQ](https://sideloadly.io/faq)

このZIPにはソースコードとビルド設定が入っています。GitHub上でのビルドとiPhone実機での撮影は、上の手順で確認してください。

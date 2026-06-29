# jazzy-training

[tier4/autoware_training](https://github.com/tier4/autoware_training)（Autoware 1.8.0 ベース）に含まれる、ROS 2 Jazzy 研修向けの補助ツールです。

## ディレクトリ構成

```
autoware_training/         ← 本リポジトリ（v0.64.2 など）
├── setup-dev-env.sh
├── repositories/
├── jazzy-training/        ← このディレクトリ
│   ├── setup.sh
│   └── ...
└── src/                   ← 受講者が vcs import で取得
```

---

## 構築手順（全体）

`jazzy-training/setup.sh` は **手順 2** として実行します。  
`setup-dev-env.sh` の後に行ってください（ROS 2 Jazzy インストール後に CycloneDDS 設定を上書きするため）。

現時点では Autoware on Jazzy において `setup-dev-env.sh` だけでは足りない課題へのワークアラウンドです（CycloneDDS の 32 ノード制限、意図しないインターフェースへの DDS 漏洩など）。upstream / ROS 側で解消されれば、本ステップは簡略化・削除される可能性があります。

```bash
# リポジトリルートで実行

# 1. 開発環境セットアップ
./setup-dev-env.sh --ros-distro jazzy
# ※ nvidia がインストール済みの場合は nvidia install で no を選択

# 2. 現時点の Jazzy / Autoware 向けワークアラウンド ← jazzy-training が担当
#    setup-dev-env.sh だけでは不足するため、以下を手動設定する:
#      - CycloneDDS ParticipantIndex=none（32 ノード制限の回避）
#      - NetworkInterface=lo（意図しないインターフェースへのトピック漏洩防止）
#    将来 Autoware / ROS 側の改善で不要になる可能性あり
cd jazzy-training && ./setup.sh && cd ..

# 3. ソース取得
mkdir -p src
vcs import src < repositories/autoware.repos
vcs import src < repositories/autoware-nightly.repos

# 4. ビルド
source /opt/ros/jazzy/setup.bash
sudo apt update && sudo apt upgrade
rosdep update
rosdep install -y --from-paths src --ignore-src --rosdistro $ROS_DISTRO
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-w"
```

ビルド後の起動では、手順 2 の設定がそのまま効きます（`~/.bashrc` にも追記済み）。

任意の確認（手順 2 の直後など）:

```bash
cd jazzy-training
./scripts/verify-setup.sh
```

---

## `./setup.sh` の役割

**単体では不十分です。** 上記手順の **1 ステップ** として実行してください。

| 手順 | 担当 |
|------|------|
| ROS 2 / 依存パッケージのインストール | `setup-dev-env.sh` |
| **CycloneDDS / ネットワーク対策** | **`jazzy-training/setup.sh`** |
| ソース取得・ビルド | `vcs import` / `colcon build` |

| 項目 | 内容 |
|------|------|
| CycloneDDS 32 ノード制限 | `ParticipantIndex=none` |
| 意図しないネットワークへのトピック漏洩 | `NetworkInterface=lo`（localhost のみ） |
| 環境変数 | `RMW_IMPLEMENTATION` / `CYCLONEDDS_URI` を `~/.bashrc` に追記 |
| ネットワークチューニング | lo マルチキャスト + sysctl（sudo 権限があれば自動） |

`setup.sh` 実行後は新しいターミナルで設定が有効です。現在のシェルでは `source jazzy-training/env.sh` でも反映できます。

---

## ホスト上の Jazzy ターミナル共通の事前準備

Planning Simulator やホスト上の Autoware 起動、`ros2 topic` 確認など、**ホスト上で Jazzy の ROS 2 を使うターミナルすべて**で必要です（コンテナ内は対象外）。

```bash
sudo ip link set lo multicast on
source jazzy-training/env.sh   # setup.sh 済みなら（~/.bashrc 追記済みの新ターミナルでも可）
```

---

## よくある罠（現時点で jazzy-training が対処している課題）

### 1. CycloneDDS 32 ノード制限

```
Failed to find a free participant index for domain 0
```

`config/cyclonedds.xml` で `ParticipantIndex=none` を設定しています。

### 2. ネットワーク / 他マシンとの干渉

`lo` 限定により、意図しないインターフェースへの ROS トピック漏洩を抑えます。

### 3. LaneletMapBin の非互換（解決不可）

Jazzy で記録した `/map/vector_map` は Humble では使えません。**Jazzy 用の map / bag を使用してください。**

### 3b. autoware_msgs のバージョン

`autoware.repos` で `autoware_msgs` は **1.13.0**（コミット固定）です。`autoware-nightly.repos` 利用時のビルドエラー（`actuation_report_stamped` 不足）を防ぐため、`repositories/autoware.repos` に含めています。手動の `git checkout` は不要です。

### 4. Docker 利用時（Planning Simulator 等）

```bash
./scripts/docker-run.sh ghcr.io/autowarefoundation/autoware:universe-jazzy

cd docker/examples/demos/planning-simulator
docker compose \
  -f docker-compose.yaml \
  -f ../../../../jazzy-training/config/docker-compose.cyclonedds-override.yaml \
  up
```

---

## 参考

- [Autoware DDS settings](https://autowarefoundation.github.io/autoware-documentation/main/installation/additional-settings-for-developers/network-configuration/dds-settings/)
- [autoware#6759](https://github.com/autowarefoundation/autoware/issues/6759)

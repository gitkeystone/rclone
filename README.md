# rfind.sh

基于 [rclone](https://rclone.org/) 的远程对象存储**关键字检索**脚本：根据关键字或通配模式，快速定位 S3 等对象存储中名称匹配的**文件或目录**。

## 特点

- **关键字子串匹配**：`rfind.sh cmjt_server` 会命中 `cmjt_server_asr_v100.tar`
- **通配模式**：支持 `*`、`?`、`[...]`（如 `*.tar`、`f?o`、`[abc]*`）
- **文件 / 目录 / 两者**：`--files-only`、`--dirs-only`，缺省两者都查
- **大小写可选**：`--ignore-case` 不区分大小写
- **多目标存储**：`--remote` / `RFIND_REMOTE` 指定任意 `remote:bucket`
- **健壮**：`set -euo pipefail`、错误输出 stderr、退出码清晰（0/2/1）

## 依赖

| 依赖 | 必需 | 说明 |
|------|------|------|
| Bash | ✅ | 4.0+ |
| rclone | ✅ | 已安装并配置好至少一个 remote（`rclone config`） |

> 脚本自身仅依赖 coreutils 基础命令；rclone 在运行前会做 `command -v` 探测，缺失时明确报错退出。

## 安装

```bash
# 赋予执行权限
chmod +x rfind.sh

# （可选）加入 PATH 以便全局调用
ln -s "$(pwd)/rfind.sh" /usr/local/bin/rfind
```

## 使用方法

```text
rfind.sh [选项] <pattern> [-- <rclone 额外参数>...]
```

### 选项

| 选项 | 说明 |
|------|------|
| `-h, --help` | 显示帮助并退出 |
| `--remote <remote:bucket>` | 指定检索目标存储（缺省用默认目标） |
| `--files-only` | 仅检索文件 |
| `--dirs-only` | 仅检索目录 |
| `--ignore-case` | 不区分大小写匹配 |
| `--` | 分隔符，其后参数透传给 rclone |

### 环境变量

| 变量 | 说明 |
|------|------|
| `RFIND_REMOTE` | 指定检索目标 `remote:bucket`（被 `--remote` 覆盖） |
| `RFIND_BUCKET` | 默认 bucket（缺省 `jiaofu-resource`） |

### 退出码

| 码 | 含义 |
|----|------|
| `0` | 成功（含无匹配） |
| `2` | 用法错误（缺少参数、非法选项） |
| `1` | 运行时失败（rclone 缺失、远程不可达、无权限等） |

### 匹配规则

- **纯关键字**（不含 `*` / `?` / `[`）→ 按**子串**匹配，等价于自动补成 `*关键字*`，可命中名字任意位置
- **含通配符**（`*` / `?` / `[`）→ 按**通配模式**匹配，且必须匹配**整个文件名**（首尾锚定），**不会**自动补前后 `*`
  - 例：`dashboard*tar` 只匹配「以 `dashboard` 开头、以 `tar` 结尾」的名字
  - 想匹配「名字中间含 `dashboard`、以 `tar` 结尾」，请写 `*dashboard*tar`
- 缺省**区分大小写**，加 `--ignore-case` 则忽略大小写

## 常用使用案例

以下示例基于已配置的 `s3:` remote（含 `jiaofu-resource` bucket）。

### 1. 按关键字查找文件

```bash
# 查找名称中包含 "cmjt_server" 的文件
./rfind.sh cmjt_server
# 输出：
#   cmjt_server_asr_v100.tar
```

### 2. 用通配符查找特定类型文件

```bash
# 查找所有 .tar 归档
./rfind.sh '*.tar'

# 只查文件、忽略大小写（*.TAR / *.Tar 也会命中）
./rfind.sh '*.tar' --files-only --ignore-case
```

### 3. 查找目录

```bash
# 查找名称含 "中" 的目录
./rfind.sh 中 --dirs-only
# 输出：
#   中化/
#   中电/
#   中航信/
#   中铁/
```

### 4. 指定要检索的目标存储

```bash
# 明确指定 remote 与 bucket
./rfind.sh 'jt-common*' --remote 's3:jiaofu-resource'

# 或用环境变量
RFIND_REMOTE='s3:jiaofu-resource' ./rfind.sh 'jt-common*'
```

### 5. 更换默认 bucket

```bash
# 默认 bucket 为 jiaofu-resource，可临时替换
RFIND_BUCKET='huhehaote-resource' ./rfind.sh '*.tar'
```

### 6. 透传 rclone 参数（限制递归深度等）

```bash
# 只搜顶层（--max-depth 1 透传给 rclone），适合大桶快速定位
./rfind.sh 'cmjt*' -- --max-depth 1
```

### 7. 本地模拟测试（无需真实 remote）

```bash
# 用 rclone 内置 :local: 后端直接检索本地目录
mkdir -p /tmp/fixture/sub && touch /tmp/fixture/a.log /tmp/fixture/sub/b.log /tmp/fixture/c.txt
./rfind.sh '*.log' --remote ':local:/tmp/fixture'
# 输出：
#   a.log
#   sub/b.log
```

### 8. 错误场景示例

```bash
./rfind.sh                     # 缺少参数 → stderr 用法提示，退出码 2
./rfind.sh 'x' --remote 'bad'  # remote 格式错误 → 退出码 2
./rfind.sh 'x' --remote 'nope:bucket'  # remote 未配置 → 退出码 1
```

## 开发与检查

```bash
# 静态检查（需 shellcheck）
shellcheck rfind.sh

# 语法检查
bash -n rfind.sh
```

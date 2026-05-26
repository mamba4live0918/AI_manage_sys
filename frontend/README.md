# AI 管理系统 — Flutter 前端

公司全链路AI赋能管理系统前端，Flutter 全端（Windows .exe / Android .apk / Web）。

## 技术栈

- Flutter 3.44 / Dart 3.12
- Riverpod 2.6.x 状态管理
- Dio 5.9.x HTTP 客户端
- GoRouter 路由
- Material Design 3

## 页面结构

| 页面 | 路由 | 说明 |
|------|------|------|
| 登录 | `/login` | 用户名+密码登录 |
| 首页仪表盘 | `/dashboard` | 系统统计+存储分布+最近动态 |
| 文件管理 | `/files` | 浏览/上传/删除/文件夹+保密级别 |
| 文件预览 | `/preview` | PDF/视频/图片/音频+水印 |
| 讲师IP | `/ip` | 文案生成（阶段二） |
| 审计日志 | `/audit` | 操作审计分页+13种筛选 |
| 用户管理 | `/users` | 部门组织架构+角色管理 |

## 三端编译

```bash
# Web（开发）
flutter build web --web-renderer canvaskit
# 然后修复 flutter_bootstrap.js 中 useLocalCanvasKit

# Windows
flutter build windows

# Android
flutter build apk
```

## Web 部署注意

`flutter build web` 后需修补 `build/web/flutter_bootstrap.js`：
1. 添加 `"useLocalCanvasKit": true`
2. 删除空的 `{}` build 配置项

## 环境配置

API 地址在 `lib/config/app_config.dart` 中配置，默认 `http://localhost:8010/api`。

# 角色首页 + 侧边栏优化

**日期**: 2026-05-29

## 一、角色首页

登录后跳转：

| accessibleModules | 跳转 |
|-------------------|------|
| 包含 "dashboard" (admin 全模块) | `/dashboard` 全公司概览 |
| 仅 "finance" | `/finance` 财务 Dashboard |
| 仅 "marketing" | `/marketing` 市场 Dashboard |
| 仅 "bidding" | `/bidding` 招投标 Dashboard |
| 仅 "pm" | `/pm` 项目 Dashboard |
| 仅 "hr" | `/hr` HR Dashboard |
| 多模块（非全模块） | `/dashboard` |

**实现**: GoRouter redirect 中根据 accessibleModules 判断，替换硬编码的 `/dashboard`。

## 二、侧边栏

- 桌面宽度：220 → 200px
- 折叠态：56px（不变）
- 移动端：滑出侧边栏（保持），宽度与桌面一致 200px
- 减少内边距，导航项字号 12→11
- 移动端侧边栏增加半透明遮罩和更流畅的滑入动画

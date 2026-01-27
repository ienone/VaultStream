# UI/UX 问题修复任务清单

## 当前优先修复项

### 1. 卡片视图间距优化 (P1) ✅
- [x] 竖屏状态下卡片间距过大 - 从20px减少到12px
- [x] 内容显示不完整 - 调整cardAspectRatio
- [x] 一行显示逻辑调整 - 窄屏(< 500px)显示1列，中屏(>= 500px)显示2列
- 涉及文件: `collection_grid.dart`, `content_card.dart`, `responsive_layout.dart`

### 2. 详情页样式统一化 (P1) ✅
- [x] 将个人信息、统计数据、tag等组合样式统一应用到所有详情页
- [x] 使用 `ContentSideInfoCard` 组件统一处理
- 涉及文件: `content_side_info_card.dart`, 各layout文件

### 3. 小红书个人信息显示问题 (P1) ✅
- [x] 统计数据显示 - 在unified_stats.dart添加小红书用户统计支持
- [x] 竖屏状态下无图时使用头像作为封面（通过getDisplayImageUrl回退逻辑）
- 涉及文件: `unified_stats.dart`, `content_parser.dart`

### 4. 小红书详情界面图片问题 (P1) ✅
- [x] 在rich_content.dart中添加小红书到showMediaGrid条件
- 涉及文件: `rich_content.dart`

### 5. 无图时使用头像作为封面 (P2) ✅
- [x] 在twitter_landscape_layout添加_buildAvatarFallback方法（显示头像+正文）
- [x] 在content_parser的getDisplayImageUrl添加头像回退逻辑
- [x] 知乎想法横屏时同时显示头像和正文
- 涉及文件: `content_parser.dart`, `twitter_landscape_layout.dart`

### 6. 知乎问题竖屏配图问题 (P2) ✅
- [x] 在rich_content.dart中为知乎问题单独处理图片显示
- [x] 图片显示顺序调整为：描述 -> 图片 -> 精选回答
- 涉及文件: `rich_content.dart`
- [] 知乎提问反向优化了：把精选回答的图片和提问本身的混在了一起，横屏状态下都显示为左侧的图片部分。竖屏状态下此前是提问图在精选回答下，我希望改成提问图在精选回答上方。
### 7. 知乎想法标题截断优化 (P1) ✅
- [x] 添加generate_pin_title函数截取到第一个标点符号
- 涉及文件: `backend/app/adapters/zhihu_parser/pin_parser.py`

### 8. 知乎问题头像与配图本地化 (P2) ✅
- [x] 在question_parser.py添加archive结构包含头像和配图
- [x] 添加问题作者头像、精选回答头像和封面到archive.images
- [x] 精选回答当前通过HTML解析获取（从entities.answers中提取）
- 涉及文件: `backend/app/adapters/zhihu_parser/question_parser.py`

### 9. 推特头像解析 (P1) ✅
- [x] API返回内容增加 `author_avatar_url` 字段
- 涉及文件: `backend/app/adapters/twitter_fx.py`

### 10. 图片查看器UI优化 (P2) ✅
- [x] 顶部计数&下载悬浮框尺寸缩小
- [x] 左右切换按钮应用模糊效果提升质感
- 涉及文件: `full_screen_gallery.dart`

### 11. 筛选界面功能修复 (P1) ✅
- [x] 重置按钮修复 - 使用_resetAll方法
- [x] 添加按tag筛选功能 - FilterChip多选
- [x] 支持多选 - Set<String> _selectedTags
- [x] Material 3 Expressive 风格优化（圆角、FilterChip等）
- [x] 多选逻辑：点击选中，再点取消
- [x] 时间筛选优化：使用快捷按钮（今天/本周/本月等）+ 自定义选项
- [x] Tag筛选UI已添加（从当前数据中获取可用tags）
- [x] 筛选逻辑在后端实现（因一次加载卡片量有限）
- 涉及文件: `filter_dialog.dart`, `collection_filter_provider.dart`, `collection_provider.dart`, `collection_page.dart`

## 未来考虑项

### 12. 目录收缩功能 (P3)
- [ ] 竖屏下文章界面有目录时，显示为可收缩的右侧竖条

### 13. 卡片长按功能 (P3)
- [ ] 删除
- [ ] 添加tag
- [ ] 重新解析
- [ ] 支持批量多选

### 14. 动画优化 (P3)
- [ ] 预见式返回支持
- [ ] 卡片放大渐变为详情界面
- [ ] 各种小部件动画

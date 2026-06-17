> 20260617

# flight-log TODO list

P0:

- [ ] admin 管理后台

P1:

- [ ] 用户点赞/编辑/删除

P2:

- [ ] ip -> 城市, 用户可选记录在每条 flight-log

## 1 admin 管理后台

- [ ] 主要面向 admin 的 JWT 登录系统

- [ ] migrate db: 回复是每条 flight-log 的该有元素, 有且仅有一条
- [ ] migrate db: 引入 edited at, 重新思考当前数据库用 id 是否合理
- [ ] migrate db: 引入 deleted (用户操作) 和 hidden (admin 操作) 两种模式, 再检查一遍当前数据库的 id 是单调递增的
- [ ] 整个系统一体的“账号”系统, 构想如下:

    ```zig
    const User = struct {
        email: ?struct {
            address: []const u8
            pwd_hash: []const u8
        }
        auth_cookies: []u8  // HTTP-only cookie sessions
    }
    ```

## 2. 用户点赞/编辑/删除

- [ ] 基于 HTTP-only cookie 的匿名身份系统: 仅写操作懒创建身份, cookie 90 天, 用于点赞/编辑/删除便利, 不作为强认证
- [ ] 用户可选 newest/best like 排序方法
- [ ] migrate db: 引入 likes
- [ ] schema: 返回 flight-log entry 时, 需要区分, 是否 liked, 是否 created_by_this_user, 有多少 likes, 返回的 created_at 迁移到 edited_at

## 3. ip -> 城市, 用户可选记录在每条 flight-log 

技术路径和实践方法研究中

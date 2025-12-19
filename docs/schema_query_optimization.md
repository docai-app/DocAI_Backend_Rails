# Schema 查询优化说明

## 问题分析

### 为什么会出现 `SELECT a.attname, format_type(...) FROM pg_attribute` 查询？

这个查询是 PostgreSQL 查询表结构的查询，通常在以下情况出现：

1. **使用 `select` 指定字段时**：
   - Rails 需要验证这些字段是否存在
   - 在多租户（Apartment）环境下，每次切换租户时可能需要重新验证
   - 如果 schema cache 未启用或失效，Rails 会从数据库查询表结构

2. **多租户环境（Apartment）**：
   - 每次切换租户（schema）时，Rails 可能需要重新加载 schema 信息
   - `config.eager_load = false` 在开发环境中，schema cache 可能没有正确工作

3. **首次访问表时**：
   - 如果 schema cache 中没有该表的信息，Rails 会查询数据库

## 解决方案

### 方案 1：移除 `select`，使用默认行为（推荐）

**优点**：
- 避免 schema 查询
- 代码更简洁
- Rails 的 `includes` 会智能处理字段选择

**缺点**：
- 会加载所有字段（但通常影响不大，因为我们已经使用了 `includes`）

### 方案 2：使用 `pluck` 直接获取值

**优点**：
- 完全避免 ActiveRecord 对象创建
- 性能最优
- 不会触发 schema 查询

**缺点**：
- 需要手动构建数据结构
- 代码稍微复杂

### 方案 3：启用 Schema Cache

**优点**：
- 避免重复的 schema 查询
- 提升整体性能

**缺点**：
- 需要配置
- 在开发环境中可能不太适用

## 推荐方案

对于当前情况，推荐**方案 1**：移除 `select`，因为：

1. 我们已经使用了 `includes` 预加载关联数据
2. `select` 在多租户环境下容易触发 schema 查询
3. 字段数量不多，加载所有字段的开销相对较小
4. 代码更简洁，维护更容易



package djshen.toolbox.tools.database.core

import kotlinx.serialization.Serializable
import java.util.UUID

/**
 * 数据库连接配置。
 *
 * @property id 唯一标识（UUID），支持重命名不丢失引用
 * @property name 连接显示名称
 * @property dbType 数据库类型，默认为 "mysql"，预留扩展 Redis/ClickHouse
 * @property host 主机地址
 * @property port 端口号
 * @property username 用户名
 * @property password 密码（明文存储）
 * @property database 默认数据库/Schema（可选）
 * @property properties 扩展属性，不同数据库类型可存储特有配置
 */
@Serializable
data class ConnectionConfig(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val dbType: String = "mysql",
    val host: String = "127.0.0.1",
    val port: Int = 3306,
    val username: String = "root",
    val password: String = "",
    val database: String = "",
    val group: String = "MySQL",
    val properties: Map<String, String> = emptyMap()
) {
    /** 构建 JDBC 连接 URL */
    fun jdbcUrl(): String = "jdbc:mysql://$host:$port/$database"
}

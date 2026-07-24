package djshen.toolbox.tools.database.shared

import androidx.compose.animation.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.unit.dp
import djshen.toolbox.common.theme.Spacing
import djshen.toolbox.common.theme.ToolBoxShapes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 树节点选中状态 */
class TreeSelection {
    var selectedDatabase by mutableStateOf("")
    var selectedTables by mutableStateOf<Set<String>>(emptySet())
    var allTablesSelected by mutableStateOf(false)

    fun selectDatabase(db: String) { selectedDatabase = db; selectedTables = emptySet(); allTablesSelected = false }
    fun toggleTable(table: String) {
        selectedTables = if (table in selectedTables) selectedTables - table else selectedTables + table
    }
    fun toggleAllTables(tables: List<String>) {
        allTablesSelected = !allTablesSelected
        selectedTables = if (allTablesSelected) tables.toSet() else emptySet()
    }
    val hasSelection: Boolean get() = selectedDatabase.isNotBlank()
    val selectedCount: Int get() = if (allTablesSelected) 999 else selectedTables.size
}

@Composable
fun SchemaTreePanel(
    databases: List<String>,
    getTables: suspend (String) -> List<String>,
    selection: TreeSelection,
    modifier: Modifier = Modifier
) {
    LazyColumn(modifier = modifier.fillMaxHeight().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)).padding(top = Spacing.sm)) {
        item { Text("选择数据库/表", Modifier.padding(horizontal = Spacing.inner, vertical = Spacing.sm), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(databases) { db -> DatabaseNode(db, getTables, selection) }
    }
}

@Composable
private fun DatabaseNode(db: String, getTables: suspend (String) -> List<String>, selection: TreeSelection) {
    var expanded by remember { mutableStateOf(false) }
    var tables by remember { mutableStateOf<List<String>?>(null) }
    val scope = rememberCoroutineScope()
    val chevron by animateFloatAsState(if (expanded) 90f else 0f, label = "chev$db")

    Column {
        Row(Modifier.fillMaxWidth().clickable {
            expanded = !expanded; selection.selectDatabase(db)
            if (expanded && tables == null) scope.launch { tables = withContext(kotlinx.coroutines.Dispatchers.IO) { getTables(db) } }
        }.padding(horizontal = Spacing.inner, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.ChevronRight, null, Modifier.size(16.dp).rotate(chevron), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(Spacing.xs))
            Text(db, style = MaterialTheme.typography.bodyMedium, color = if (selection.selectedDatabase == db) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
        }
        AnimatedVisibility(expanded) {
            Column {
                tables?.let { tbls ->
                    Row(Modifier.fillMaxWidth().clickable { selection.toggleAllTables(tbls) }.padding(start = 48.dp, end = Spacing.inner, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(selection.allTablesSelected, { selection.toggleAllTables(tbls) }, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(Spacing.xs))
                        Text("全选 (${tbls.size})", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    tbls.forEach { table ->
                        Row(Modifier.fillMaxWidth().clickable { selection.toggleTable(table) }.padding(start = 48.dp, end = Spacing.inner, top = 1.dp, bottom = 1.dp), verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(table in selection.selectedTables, { selection.toggleTable(table) }, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(Spacing.xs))
                            Icon(Icons.Default.TableChart, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                            Spacer(Modifier.width(Spacing.xs))
                            Text(table, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
            }
        }
    }
}

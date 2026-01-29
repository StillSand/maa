"""
MAA 任务摘要格式化工具
提供统一的格式化逻辑，供 GitHub Summary 和 Telegram 消息使用
"""

# 任务类型图标映射
TASK_ICONS = {
    '开始唤醒': '🌅',
    '公开招募': '👥',
    '自动战斗': '⚔️',
    '基建换班': '🏭',
    '信用商店': '🏪',
    '领取奖励': '🎁',
    '关闭游戏': '🔚',
    '访问好友': '👋',
    '收取信用': '💰',
    '生息演算': '🧮',
    '保全派驻': '🛡️',
}


def parse_summary(summary_text, start_date=None):
    """
    解析 MAA 摘要文本，提取任务信息
    
    Args:
        summary_text: MAA 摘要文本
        start_date: 开始日期（格式：YYYY-MM-DD），用于补全任务时间
        
    Returns:
        list: 任务列表，每个任务是一个字典 {'name': str, 'title': str, 'details': list}
    """
    if not summary_text:
        return []
    
    lines = summary_text.splitlines()
    tasks = []
    current_task = None
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # 检测任务分隔线
        if stripped and stripped.count('-') > len(stripped) * 0.75:
            # 检查下一行是否是任务标题
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                if next_line and '[' in next_line and ']' in next_line:
                    # 保存上一个任务
                    if current_task:
                        tasks.append(current_task)
                    
                    # 提取任务名称
                    task_name = next_line[next_line.find('[')+1:next_line.find(']')]
                    
                    # 解析并重新格式化任务标题
                    title = next_line
                    if start_date:
                        # 匹配时间格式：[任务名] HH:MM:SS - HH:MM:SS (耗时) 状态
                        import re
                        # 匹配格式：[任务名] 开始时间 - 结束时间 (耗时) 状态
                        pattern = r'\[([^\]]+)\]\s+(\d{2}:\d{2}:\d{2})\s*-\s*(\d{2}:\d{2}:\d{2})\s+\(([^)]+)\)\s+(\w+)'
                        match = re.match(pattern, next_line)
                        if match:
                            task_name_match = match.group(1)
                            start_time = match.group(2)
                            end_time = match.group(3)
                            duration = match.group(4)
                            status = match.group(5)
                            
                            # 重新格式化为统一格式
                            # 根据状态显示不同的图标和文本
                            if status == 'Completed':
                                status_display = '✅ Completed'
                            elif status == 'Failed':
                                status_display = '❌ Failed'
                            else:
                                status_display = f'⚠️ {status}'
                            
                            title = f"[{task_name_match}] 🕐 **开始:** {start_date} {start_time} | 🏁 **结束:** {start_date} {end_time} | ⏱️ **耗时:** {duration} | {status_display}"
                    
                    # 创建新任务
                    current_task = {
                        'name': task_name,
                        'title': title,
                        'details': []
                    }
            continue
        
        # 跳过已经作为标题输出的行
        if i > 0 and lines[i-1].strip().count('-') > len(lines[i-1].strip()) * 0.75:
            if stripped and '[' in stripped and ']' in stripped:
                continue
        
        # 收集任务详情
        if current_task and stripped:
            current_task['details'].append(line)
    
    # 保存最后一个任务
    if current_task:
        tasks.append(current_task)
    
    return tasks


def format_task_details(details, use_table=True):
    """
    格式化任务详情，增强可读性
    
    Args:
        details: 任务详情行列表
        use_table: 是否使用表格格式（True=GitHub表格，False=Telegram纯文本）
        
    Returns:
        list: 格式化后的详情行
    """
    if not details:
        return []
    
    formatted = []
    i = 0
    
    while i < len(details):
        line = details[i]
        stripped = line.strip()
        
        # 处理招募标签
        if 'Detected tags:' in stripped:
            if use_table:
                formatted.append('**检测到的标签：**\n')
                formatted.append('| 编号 | 稀有度 | 标签 | 状态 |')
                formatted.append('|------|--------|------|------|')
            else:
                formatted.append('*检测到的标签：*')
            
            i += 1
            while i < len(details):
                tag_line = details[i].strip()
                
                # 如果是编号开头的标签行，解析它
                if tag_line and tag_line[0].isdigit() and '. ' in tag_line:
                    parts = tag_line.split('. ', 1)
                    if len(parts) == 2:
                        num = parts[0]
                        content = parts[1]
                        
                        # 分离稀有度、标签和状态
                        if '★' in content:
                            # 找到星号后的第一个空格
                            first_space = content.find(' ', content.rfind('★') + 1)
                            if first_space > 0:
                                rarity = content[:first_space]
                                rest = content[first_space+1:]
                                
                                # 分离标签和状态
                                if ', Recruited' in rest:
                                    tags = rest.replace(', Recruited', '')
                                    status = '✅ 已招募'
                                elif ', Refreshed' in rest:
                                    tags = rest.replace(', Refreshed', '')
                                    status = '🔄 已刷新'
                                else:
                                    tags = rest
                                    status = '-'
                                
                                if use_table:
                                    formatted.append(f'| {num} | {rarity} | {tags} | {status} |')
                                else:
                                    formatted.append(f'  {num}. {rarity} {tags} - {status}')
                    i += 1
                # 如果不是标签行，说明标签部分结束
                elif not tag_line or (tag_line and not tag_line[0].isdigit()):
                    break
                else:
                    i += 1
            
            # 添加招募统计
            formatted.append('')
            recruited_count = 0
            refreshed_count = 0
            
            while i < len(details):
                stat_line = details[i].strip()
                if 'Recruited' in stat_line and 'times' in stat_line:
                    recruited_count = stat_line.split()[1]
                    if use_table:
                        formatted.append(f'✅ **已招募**: {recruited_count} 次')
                    else:
                        formatted.append(f'✅ 已招募: {recruited_count} 次')
                    i += 1
                elif 'Refreshed' in stat_line and 'times' in stat_line:
                    refreshed_count = stat_line.split()[1]
                    if use_table:
                        formatted.append(f'🔄 **已刷新**: {refreshed_count} 次')
                    else:
                        formatted.append(f'🔄 已刷新: {refreshed_count} 次')
                    i += 1
                else:
                    break
            continue
        
        # 处理战斗掉落
        if 'Fight' in stripped and 'drops:' in stripped:
            # 提取关卡和次数: "Fight 1-7 12 times, drops:"
            fight_info = stripped.replace('drops:', '').strip()
            if use_table:
                formatted.append(f'**{fight_info}**\n')
            else:
                formatted.append(f'*{fight_info}*')
            
            # 收集所有掉落行
            drop_lines = []
            i += 1
            while i < len(details):
                drop_line = details[i].strip()
                if not drop_line:
                    i += 1
                    continue
                if 'total drops:' in drop_line:
                    break
                if drop_line and drop_line[0].isdigit() and '. ' in drop_line:
                    drop_lines.append(drop_line)
                i += 1
            
            # 显示掉落表格
            if drop_lines:
                if use_table:
                    formatted.append('| 次数 | 物品 | 数量 |')
                    formatted.append('|------|------|------|')
                    for drop_line in drop_lines:
                        parts = drop_line.split('. ', 1)
                        if len(parts) == 2:
                            round_num = parts[0]
                            items_text = parts[1]
                            
                            # 解析每个物品
                            items = [item.strip() for item in items_text.split(',')]
                            for idx, item in enumerate(items):
                                # 分离物品名称和数量
                                if ' × ' in item:
                                    item_parts = item.split(' × ')
                                    item_name = item_parts[0]
                                    item_count = item_parts[1] if len(item_parts) > 1 else '1'
                                else:
                                    item_name = item
                                    item_count = '1'
                                
                                # 第一个物品显示次数，其他物品次数列为空
                                if idx == 0:
                                    formatted.append(f'| 第 {round_num} 次 | {item_name} | {item_count} |')
                                else:
                                    formatted.append(f'| | {item_name} | {item_count} |')
                else:
                    # Telegram 纯文本格式
                    for drop_line in drop_lines:
                        parts = drop_line.split('. ', 1)
                        if len(parts) == 2:
                            round_num = parts[0]
                            items_text = parts[1]
                            formatted.append(f'  第 {round_num} 次: {items_text}')
            
            # 处理总计
            if i < len(details) and 'total drops:' in details[i].strip():
                total_line = details[i].strip()
                total_items_text = total_line.replace('total drops:', '').strip()
                
                formatted.append('')
                if use_table:
                    formatted.append('**📦 总计掉落：**\n')
                    formatted.append('| 物品 | 总数量 |')
                    formatted.append('|------|--------|')
                    
                    # 解析总计物品
                    total_items = [item.strip() for item in total_items_text.split(',')]
                    for item in total_items:
                        if ' × ' in item:
                            item_parts = item.split(' × ')
                            item_name = item_parts[0]
                            item_count = item_parts[1] if len(item_parts) > 1 else '1'
                            formatted.append(f'| {item_name} | {item_count} |')
                else:
                    formatted.append('*📦 总计掉落：*')
                    formatted.append(f'  {total_items_text}')
                
                i += 1
            continue
        
        # 处理基建设施
        if any(keyword in stripped for keyword in ['Mfg(', 'Trade(', 'Power', 'Control', 'Reception', 'Dorm', 'Office']):
            # 收集所有基建行
            facility_lines = [line]
            i += 1
            while i < len(details):
                next_line = details[i].strip()
                if any(keyword in next_line for keyword in ['Mfg(', 'Trade(', 'Power', 'Control', 'Reception', 'Dorm', 'Office']):
                    facility_lines.append(details[i])
                    i += 1
                else:
                    break
            
            # 生成基建表格或列表
            if use_table:
                formatted.append('**基建设施：**\n')
                formatted.append('| 设施类型 | 干员 |')
                formatted.append('|----------|------|')
            else:
                formatted.append('*基建设施：*')
            
            for fac_line in facility_lines:
                fac_stripped = fac_line.strip()
                if ' with operators: ' in fac_stripped:
                    parts = fac_stripped.split(' with operators: ')
                    facility = parts[0]
                    operators = parts[1] if len(parts) > 1 else 'unknown'
                    
                    # 美化设施名称
                    facility_icon = {
                        'Mfg(PureGold)': '🏭 制造站(赤金)',
                        'Mfg': '🏭 制造站',
                        'Trade(Money)': '💰 贸易站(龙门币)',
                        'Trade': '💰 贸易站',
                        'Power': '⚡ 发电站',
                        'Control': '🎮 控制中枢',
                        'Reception': '🏢 会客室',
                        'Dorm': '🛏️ 宿舍',
                        'Office': '📋 办公室'
                    }.get(facility, facility)
                    
                    if use_table:
                        formatted.append(f'| {facility_icon} | {operators} |')
                    else:
                        formatted.append(f'  {facility_icon}: {operators}')
            continue
        
        # 其他行直接添加
        formatted.append(line)
        i += 1
    
    return formatted



def format_for_github(summary_text, start_date=None):
    """
    格式化为 GitHub Actions Summary (Markdown)
    
    Args:
        summary_text: MAA 摘要文本
        start_date: 开始日期（格式：YYYY-MM-DD），用于补全任务时间
        
    Returns:
        str: Markdown 格式的文本
    """
    tasks = parse_summary(summary_text, start_date)
    
    if not tasks:
        return "*无报告信息*\n"
    
    lines = []
    for i, task in enumerate(tasks, 1):
        icon = TASK_ICONS.get(task['name'], '📋')
        
        # 任务标题（不在代码块内，不可复制）
        lines.append(f"### {icon} 任务 {i}: {task['title']}\n")
        
        # 任务详情（使用折叠块，表格在外面可以渲染）
        if task['details']:
            lines.append("<details open>")
            lines.append("<summary>📋 详细信息</summary>\n")
            
            # 格式化详情（表格会在 Markdown 中渲染）
            formatted_details = format_task_details(task['details'])
            for detail in formatted_details:
                lines.append(detail)
            
            lines.append("\n</details>\n")
        # 如果没有详细信息，不显示任何内容
    
    return '\n'.join(lines)


def format_for_telegram(summary_text, start_date=None):
    """
    格式化为 Telegram 消息 (纯文本，不使用表格)
    
    Args:
        summary_text: MAA 摘要文本
        start_date: 开始日期（格式：YYYY-MM-DD），用于补全任务时间
        
    Returns:
        str: 纯文本格式的消息
    """
    tasks = parse_summary(summary_text, start_date)
    
    if not tasks:
        return '无报告信息'
    
    lines = []
    for i, task in enumerate(tasks):
        icon = TASK_ICONS.get(task['name'], '📋')
        
        # 任务之间添加空行（第一个任务除外）
        if i > 0:
            lines.append('')
        
        # 任务标题
        lines.append(f"{icon} *{task['name']}*")
        lines.append(task['title'].replace('**', '').replace('[', '').replace(']', ''))
        
        # 任务详情（只有存在详情时才显示）
        if task['details']:
            formatted_details = format_task_details(task['details'], use_table=False)
            for detail in formatted_details:
                lines.append(detail)
        # 如果没有详细信息，不显示任何内容
    
    return '\n'.join(lines)

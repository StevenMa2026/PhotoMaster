import Foundation
import EventKit

class DateUtil {
    
    // 缓存节假日判断结果，避免重复查询
    private static var holidayCache: [String: Bool] = [:]
    
    /// 检查指定日期是否是节假日（考虑调休补班）
    /// - 如果是周末但被标记为工作日（调休），则不是节假日
    /// - 如果是工作日但被标记为节假日，则是节假日
    static func isHoliday(date: Date) -> Bool {
        let calendar = Calendar.current
        
        // 生成缓存键
        let dateString = dateFormat(date: date, format: "yyyy-MM-dd")
        if let cached = holidayCache[dateString] {
            return cached
        }
        
        let eventStore = EKEventStore()
        
        // 请求日历访问权限
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != .authorized {
            // 如果没有权限，使用简单的周末判断作为后备
            // 注意：这种情况下无法处理调休补班
            let isWeekend = calendar.isDateInWeekend(date)
            holidayCache[dateString] = isWeekend
            return isWeekend
        }
        
        // 获取系统日历中的节假日
        let calendars = eventStore.calendars(for: .event)
        let holidayCalendars = calendars.filter { calendar in
            calendar.title.contains("节假日") || 
            calendar.title.contains("Holiday") || 
            calendar.title.contains("Chinese") ||
            calendar.title.contains("中国") ||
            calendar.source.title.contains("iCloud")
        }
        
        // 检查当天是否有节假日事件
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: holidayCalendars)
        let events = eventStore.events(matching: predicate)
        
        // 如果有节假日事件，则是节假日
        let hasHolidayEvent = !events.isEmpty
        
        // 特殊处理：周末如果有事件，可能是调休上班
        let isWeekend = calendar.isDateInWeekend(date)
        
        var result: Bool
        if isWeekend {
            // 周末：如果有事件，可能是调休上班（不是节假日）
            // 如果没有事件，是正常周末（是节假日）
            result = !hasHolidayEvent
        } else {
            // 工作日：如果有事件，是节假日（放假）
            // 如果没有事件，是正常工作日（不是节假日）
            result = hasHolidayEvent
        }
        
        holidayCache[dateString] = result
        return result
    }
    
    /// 格式化日期为字符串
    static func dateFormat(date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.calendar = Calendar.current
        return formatter.string(from: date)
    }
    
    /// 清空缓存（在重新扫描时调用）
    static func clearCache() {
        holidayCache.removeAll()
    }
}
//
//  CEventManager.swift
//
//  Created by Danilo Priore on 23/05/18.
//  Copyright © 2018 Danilo Priore. All rights reserved.
//

import UIKit
import Foundation
import EventKit

typealias CEventManagerCompletion = (_ eventIdentifier: String?, _ error: Error?) -> Void

enum CEventAlarmType: TimeInterval {
    case nothing = -1
    case atTimeOfEvent = 0
    case fiveMinutesBefore = -300
    case fifteenMinutesBefore = -900
    case thirtyMinutesBefore = -1800
    case oneHourBefore = -3600
    case twoHoursBefore = -7200
    case oneDayBefore = -86400
    case twoDaysBefore = -172800
    
    static let allValues = [nothing,
                            atTimeOfEvent,
                            fiveMinutesBefore,
                            fifteenMinutesBefore,
                            thirtyMinutesBefore,
                            oneHourBefore,
                            twoHoursBefore,
                            oneDayBefore,
                            twoDaysBefore]
    
    static let strings = ["Nothing",
                          "At time of event",
                          "5 minutes before",
                          "15 minutes before",
                          "30 minutes before",
                          "1 hour before",
                          "2 hours before",
                          "1 day before",
                          "2 days before"]
    
    
    static func interval(string: String) -> CEventAlarmType {
        let index = strings.index(of: string)
        return allValues[index ?? 0]
    }
}

enum CEventRecurrenceFrequency {
    
    static let allValues = [nil,
                            EKRecurrenceFrequency.daily,
                            EKRecurrenceFrequency.weekly,
                            EKRecurrenceFrequency.monthly,
                            EKRecurrenceFrequency.yearly]
    
    static let strings = ["Not repeated",
                          "Everyday",
                          "Every week",
                          "Every month",
                          "Every year"]
    
    static func value(string: String?) -> EKRecurrenceFrequency? {
        if let str = string {
            let index = strings.index(of: str)
            return allValues[index ?? 0]
        }
        
        return nil
    }
    
}

class CEventManager {
    
    static let shared = CEventManager()
    
    var calendarName: String = "MyCalendar"
    var timeZone: TimeZone? = TimeZone.current
    var color: UIColor = UIColor.magenta
    
    private var eventStore: EKEventStore = EKEventStore()
    
    init() {
        
        UIApplication.shared.setMinimumBackgroundFetchInterval(
            UIApplicationBackgroundFetchIntervalMinimum
        )

        // intercepts changes to the device calendar
        NotificationCenter.default.addObserver(self, selector: #selector(self.eventStoreChangedNotification(_:)), name: NSNotification.Name.EKEventStoreChanged , object: nil)
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func addEvent(title: String? = nil,
                         date: Date? = nil,
                         end: Date? = nil,
                         endDateRecurrency: Date? = nil,
                         alarms: [Any]? = nil,
                         recurrency: EKRecurrenceFrequency? = nil,
                         allDay: Bool? = false,
                         notes: String? = nil,
                         location: EKStructuredLocation? = nil,
                         completion: CEventManagerCompletion? = nil) {
        
        var err: Error?
        var eventIdentifier: String?
        
        let event = EKEvent(eventStore: self.eventStore)
        event.title = title
        event.startDate = date
        event.endDate = (end != nil) ? end : date?.addingTimeInterval(3600)
        
        event.notes = notes
        event.calendar = self.getCalendar(eventStore: self.eventStore)
        event.isAllDay = allDay ?? false
        event.structuredLocation = location
        event.timeZone = timeZone
        
        if recurrency != nil {
            var endRule = end != nil ? EKRecurrenceEnd(end: end!) : nil
            if endDateRecurrency != nil {
                endRule = EKRecurrenceEnd(end: endDateRecurrency!)
            }
            
            let rule = EKRecurrenceRule(recurrenceWith: recurrency!, interval: 1, end: endRule)
            event.addRecurrenceRule(rule)
        }
        
        if alarms != nil {
            for alarm in alarms! {
                if let date = alarm as? Date  {
                    let ekAlarm = EKAlarm(absoluteDate: date)
                    event.addAlarm(ekAlarm)
                }
                else if let interval = alarm as? TimeInterval, interval != -1 {
                    let ekAlarm = EKAlarm(relativeOffset: interval)
                    event.addAlarm(ekAlarm)
                }
            }
        }
        
        do {
            try self.eventStore.save(event, span: .thisEvent)
            eventIdentifier = event.eventIdentifier
        } catch {
            err = error
        }
        
        completion?(eventIdentifier, err)
        
    }
    
    func removeEvents(eventIDs: [String?]) {
        
        let filled = eventIDs.filter({ $0 != nil }) as! [String]
        let unique = Array(Set(filled))
        for eventId in unique {
            if !eventId.isEmpty, let event = self.eventStore.event(withIdentifier: eventId) {
                do {
                    try self.eventStore.remove(event, span: .futureEvents)
                } catch {
                    // NOP
                }
            }
        }
    }
    
    private func getCalendar(eventStore: EKEventStore) -> EKCalendar? {
        
        if let calendar = eventStore.calendar(withIdentifier: calendarName) {
            return calendar
        }
        
        let calendars = eventStore.calendars(for: .event)
        if let calendar = calendars.filter({ $0.title == calendarName }).first {
            return calendar
        }
        
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        
        calendar.title = calendarName
        calendar.cgColor = self.color.cgColor
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
        
        return saveCalendar(calendar: calendar, store: eventStore, ignoreErrors: false)
    }
    
    private func saveCalendar(calendar: EKCalendar, store: EKEventStore, ignoreErrors: Bool) -> EKCalendar? {
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            debugPrint(error.localizedDescription)
            
            if !ignoreErrors, let local = eventStore.sources.filter({ $0.sourceType == .local }).first {
                calendar.source = local
                return saveCalendar(calendar: calendar, store: store, ignoreErrors: true);
            }
            
            return eventStore.defaultCalendarForNewEvents
        }
        
        return calendar
    }
    
    // MARK: - Norifications
    
    @objc func eventStoreChangedNotification(_ note: Notification?) {
        // TODO: recovery of deleted event
    }
    
}

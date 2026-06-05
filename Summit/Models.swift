import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable { 
    case checking, savings, creditCard, loan, investment, retirement
    var id: String { rawValue } 
}

struct Account: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var type: AccountType
    var balance: Decimal
    var currencyCode: String = "USD"
}

struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var accountId: UUID
    var date: Date
    var amount: Decimal // positive for inflow, negative for outflow
    var merchant: String
    var memo: String?
    var categoryId: UUID?
    var cleared: Bool = false
}

struct CategoryGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sort: Int
}

struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var groupId: UUID
    var name: String
    var sort: Int
}

enum GoalType: String, Codable { 
    case monthlyAmount, byDateTarget, savingsTarget 
}

struct Goal: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var categoryId: UUID
    var type: GoalType
    var targetAmount: Decimal
    var targetDate: Date?
}

enum ScheduledKind: String, Codable { 
    case bill, paycheck, subscription 
}

struct ScheduledItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ScheduledKind
    var name: String
    var amount: Decimal // positive for income, negative for expense
    var nextDate: Date
    var intervalDays: Int // simple recurrence for scaffold
    var accountId: UUID?
}

struct BudgetMonth: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var year: Int
    var month: Int // 1...12
    var allocations: [UUID: Decimal] // categoryId -> assigned amount for this month
    var carryover: Decimal // unassigned carryover from previous month

    var dateComponents: DateComponents { DateComponents(year: year, month: month) }
}

extension Decimal {
    static var zeroD: Decimal { 0 }
}

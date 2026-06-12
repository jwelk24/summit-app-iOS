import Foundation
import SwiftData

@Model
final class AccountModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: AccountType
    var balance: Decimal
    var currencyCode: String

    @Relationship(deleteRule: .cascade, inverse: \TransactionModel.account)
    var transactions: [TransactionModel]

    init(id: UUID = UUID(), name: String, type: AccountType, balance: Decimal = 0, currencyCode: String = "USD") {
        self.id = id
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.transactions = []
    }
}

@Model
final class CategoryGroupModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var sort: Int

    @Relationship(deleteRule: .cascade, inverse: \CategoryModel.group)
    var categories: [CategoryModel]

    init(id: UUID = UUID(), name: String, sort: Int) {
        self.id = id
        self.name = name
        self.sort = sort
        self.categories = []
    }
}

@Model
final class CategoryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var sort: Int

    var group: CategoryGroupModel?

    @Relationship(deleteRule: .nullify, inverse: \TransactionModel.category)
    var transactions: [TransactionModel]

    @Relationship(deleteRule: .cascade, inverse: \GoalModel.category)
    var goals: [GoalModel]

    @Relationship(deleteRule: .cascade, inverse: \BudgetAllocationModel.category)
    var allocations: [BudgetAllocationModel]

    init(id: UUID = UUID(), name: String, sort: Int, group: CategoryGroupModel? = nil) {
        self.id = id
        self.name = name
        self.sort = sort
        self.group = group
        self.transactions = []
        self.goals = []
        self.allocations = []
    }
}

@Model
final class TransactionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var amount: Decimal
    var merchant: String
    var memo: String?
    var cleared: Bool

    var account: AccountModel?
    var category: CategoryModel?

    init(id: UUID = UUID(), date: Date, amount: Decimal, merchant: String, memo: String? = nil, cleared: Bool = false, account: AccountModel? = nil, category: CategoryModel? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.memo = memo
        self.cleared = cleared
        self.account = account
        self.category = category
    }
}

@Model
final class GoalModel {
    @Attribute(.unique) var id: UUID
    var type: GoalType
    var targetAmount: Decimal
    var targetDate: Date?

    var category: CategoryModel?

    init(id: UUID = UUID(), type: GoalType, targetAmount: Decimal, targetDate: Date? = nil, category: CategoryModel? = nil) {
        self.id = id
        self.type = type
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.category = category
    }
}

@Model
final class ScheduledItemModel {
    @Attribute(.unique) var id: UUID
    var kind: ScheduledKind
    var name: String
    var amount: Decimal
    var nextDate: Date
    var intervalDays: Int

    var account: AccountModel?
    var category: CategoryModel?

    init(id: UUID = UUID(), kind: ScheduledKind, name: String, amount: Decimal, nextDate: Date, intervalDays: Int, account: AccountModel? = nil, category: CategoryModel? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.amount = amount
        self.nextDate = nextDate
        self.intervalDays = intervalDays
        self.account = account
        self.category = category
    }
}

@Model
final class BudgetMonthModel {
    @Attribute(.unique) var id: UUID
    var year: Int
    var month: Int
    var carryover: Decimal

    @Relationship(deleteRule: .cascade, inverse: \BudgetAllocationModel.month)
    var allocations: [BudgetAllocationModel]

    init(id: UUID = UUID(), year: Int, month: Int, carryover: Decimal = 0) {
        self.id = id
        self.year = year
        self.month = month
        self.carryover = carryover
        self.allocations = []
    }
}

@Model
final class BudgetAllocationModel {
    @Attribute(.unique) var id: UUID
    var amount: Decimal

    var category: CategoryModel?
    var month: BudgetMonthModel?

    init(id: UUID = UUID(), amount: Decimal, category: CategoryModel? = nil, month: BudgetMonthModel? = nil) {
        self.id = id
        self.amount = amount
        self.category = category
        self.month = month
    }
}

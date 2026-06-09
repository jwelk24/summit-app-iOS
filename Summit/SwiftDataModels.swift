import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking, savings, creditCard, loan, investment, retirement
    var id: String { rawValue }
}

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String // store rawValue of AccountType for simplicity in SwiftData
    var balance: Decimal
    var currencyCode: String

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]

    init(id: UUID = UUID(), name: String, type: AccountType, balance: Decimal = 0, currencyCode: String = "USD") {
        self.id = id
        self.name = name
        self.type = type.rawValue
        self.balance = balance
        self.currencyCode = currencyCode
        self.transactions = []
    }

    var accountType: AccountType {
        get { AccountType(rawValue: type) ?? .checking }
        set { type = newValue.rawValue }
    }
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var date: Date
    var amount: Decimal // positive for inflow, negative for outflow
    var merchant: String
    var memo: String?
    var cleared: Bool

    @Relationship var account: Account?

    init(id: UUID = UUID(), date: Date, amount: Decimal, merchant: String, memo: String? = nil, cleared: Bool = false, account: Account? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.memo = memo
        self.cleared = cleared
        self.account = account
    }
}

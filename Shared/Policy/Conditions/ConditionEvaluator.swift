import Foundation

protocol ConditionEvaluator {
    func evaluate(question: NoemaQuestion, runtimeState: RuntimeState) -> Bool
}

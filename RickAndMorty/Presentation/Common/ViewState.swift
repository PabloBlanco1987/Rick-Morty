import Foundation

// El estado de una pantalla, en un solo valor.
// La alternativa de siempre —isLoading, items y errorMessage por separado— permite
// escribir estados que no existen: cargando y con error a la vez, o una lista vacía
// sin saber si es que no hay nada o es que todavía no ha llegado. Con un enum esas
// combinaciones no se pueden ni teclear, y la vista se convierte en un switch
// exhaustivo que el compilador obliga a cubrir entero.
enum ViewState<Value> {
    // Todavía no se ha pedido nada. Distinto de .loading: al volver a la pantalla
    // sirve para saber si hay que cargar o si ya hay algo cargado.
    case idle
    case loading
    case loaded(Value)
    // Ha ido bien y no hay nada que enseñar. Es un resultado, no un fallo, y lo que
    // se pinta no se parece en nada a una pantalla de error, así que tiene su caso.
    case empty
    case failed(AppError)
}

extension ViewState: Equatable where Value: Equatable {}
extension ViewState: Sendable where Value: Sendable {}

extension ViewState {
    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }
}

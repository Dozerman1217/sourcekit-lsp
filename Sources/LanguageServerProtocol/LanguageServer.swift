//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKSupport
import Dispatch

/// An abstract language server.
///
/// This class is designed to be the base class for a concrete language server. It provides the message handling interface along with some common functionality like request handler registration.
open class LanguageServer: LanguageServerEndpoint {

  /// The connection to the language client.
  public let client: Connection

  public init(client: Connection) {
    self.client = client
    super.init()
  }
}

/// An abstract language client or server.
open class LanguageServerEndpoint {

  /// The server's request queue.
  ///
  /// All incoming requests start on this queue, but should reply or move to another queue as soon as possible to avoid blocking.
  public let queue: DispatchQueue = DispatchQueue(label: "language-server-queue", qos: .userInitiated)

  private var requestHandlers: [ObjectIdentifier: Any] = [:]

  private var notificationHandlers: [ObjectIdentifier: Any] = [:]

  public struct RequestCancelKey: Hashable {
    public var client: ObjectIdentifier
    public var request: RequestID
    public init(client: ObjectIdentifier, request: RequestID) {
      self.client = client
      self.request = request
    }
  }

  /// The set of outstanding requests that may be cancelled.
  public var requestCancellation: [RequestCancelKey: CancellationToken] = [:]

  /// Creates a language server for the given client.
  public init() {

    _registerBuiltinHandlers()
  }

  /// Register handlers for all known requests and notifications. *Subclasses must override*.
  ///
  /// - returns: true if this server expects to handle all messages in the message registry.
  open func _registerBuiltinHandlers() {
    fatalError("subclass must override")
  }

  /// Handle an unknown request.
  ///
  /// By default, replies with `methodNotFound` error.
  open func _handleUnknown<R>(_ request: Request<R>) {
    request.reply(.failure(ResponseError.methodNotFound(R.method)))
  }

  /// Handle an unknown notification.
  open func _handleUnknown<N>(_ notification: Notification<N>) {
    // Do nothing.
  }

  open func _logRequest<R>(_ request: Request<R>) {
    logAsync { _ in
      "\(type(of: self)): \(request)"
    }
  }
  open func _logNotification<N>(_ notification: Notification<N>) {
    logAsync { _ in
      "\(type(of: self)): \(notification)"
    }
  }
  open func _logResponse<Response>(_ result: LSPResult<Response>, id: RequestID, method: String) {
    logAsync { _ in
      """
      \(type(of: self)): Response<\(method)>(
        \(result)
      )
      """
    }
  }
}

extension LanguageServerEndpoint {
  // MARK: Request registration.

  /// Register the given request handler, which must be a method on `self`.
  ///
  /// Must be called on `queue`.
  public func _register<Server, R>(_ requestHandler: @escaping (Server) -> (Request<R>) -> ()) {
    // We can use `unowned` here because the handler is run synchronously on `queue`.
    precondition(self is Server)
    requestHandlers[ObjectIdentifier(R.self)] = { [unowned self] request in
      requestHandler(self as! Server)(request)
    }
  }

  /// Register the given notification handler, which must be a method on `self`.
  ///
  /// Must be called on `queue`.
  public func _register<Server, N>(_ noteHandler: @escaping (Server) -> (Notification<N>) -> ()) {
    // We can use `unowned` here because the handler is run synchronously on `queue`.
    notificationHandlers[ObjectIdentifier(N.self)] = { [unowned self] note in
      noteHandler(self as! Server)(note)
    }
  }

  /// Register the given request handler.
  ///
  /// Must be called on `queue`.
  public func _register<R>(_ requestHandler: @escaping (Request<R>) -> ()) {
    requestHandlers[ObjectIdentifier(R.self)] = requestHandler
  }

  /// Register the given notification handler.
  ///
  /// Must be called on `queue`.
  public func _register<N>(_ noteHandler: @escaping (Notification<N>) -> ()) {
    notificationHandlers[ObjectIdentifier(N.self)] = noteHandler
  }

  /// Register the given request handler.  **For test messages only**.
  public func register<R>(_ requestHandler: @escaping (Request<R>) -> ()) {
    queue.sync { _register(requestHandler) }
  }

  /// Register the given notification handler.  **For test messages only**.
  public func register<N>(_ noteHandler: @escaping (Notification<N>) -> ()) {
    queue.sync { _register(noteHandler) }
  }
}

extension LanguageServerEndpoint: MessageHandler {

  // MARK: MessageHandler interface

  public func handle<N>(_ params: N, from clientID: ObjectIdentifier) where N: NotificationType {
    queue.async {

      let notification = Notification(params, clientID: clientID)

      self._logNotification(notification)

      guard let handler = self.notificationHandlers[ObjectIdentifier(N.self)] as? ((Notification<N>) -> ()) else {
        self._handleUnknown(notification)
        return
      }
      handler(notification)
    }
  }

  public func handle<R>(_ params: R, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (LSPResult<R.Response >) -> ()) where R: RequestType {

    queue.async {

      let cancellationToken = CancellationToken()
      let key = RequestCancelKey(client: clientID, request: id)

      self.requestCancellation[key] = cancellationToken

      let request = Request(params, id: id, clientID: clientID, cancellation: cancellationToken, reply: { [weak self] result in
        self?.requestCancellation[key] = nil
        reply(result)
        self?._logResponse(result, id: id, method: R.method)
      })

      self._logRequest(request)

      guard let handler = self.requestHandlers[ObjectIdentifier(R.self)] as? ((Request<R>) -> ()) else {
        self._handleUnknown(request)
        return
      }

      handler(request)

    }
  }
}

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

import LanguageServerProtocol
import SKTestSupport
import XCTest

// Workaround ambiguity with Foundation.
typealias Notification = LanguageServerProtocol.Notification

class ConnectionTests: XCTestCase {

  var connection: TestLocalConnection! = nil

  override func setUp() {
    connection = TestLocalConnection()
  }

  override func tearDown() {
    connection.close()
  }

  func testEcho() {
    let client = connection.client
    let expectation = self.expectation(description: "response received")

    _ = client.send(EchoRequest(string: "hello!")) { resp in
      XCTAssertEqual(try! resp.dematerialize(), "hello!")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10)
  }

  func testEchoError() {
    let client = connection.client
    let expectation = self.expectation(description: "response received 1")
    let expectation2 = self.expectation(description: "response received 2")

    _ = client.send(EchoError(code: nil)) { resp in
      XCTAssertEqual(try! resp.dematerialize(), VoidResponse())
      expectation.fulfill()
    }

    _ = client.send(EchoError(code: .unknownErrorCode, message: "hey!")) { resp in
      XCTAssertEqual(resp, LSPResult<VoidResponse>.failure(ResponseError(code: .unknownErrorCode, message: "hey!")))
      expectation2.fulfill()
    }

    waitForExpectations(timeout: 10)
  }

  func testEchoNote() {
    let client = connection.client
    let expectation = self.expectation(description: "note received")

    client.handleNextNotification { (note: Notification<EchoNotification>) in
      XCTAssertEqual(note.params.string, "hello!")
      expectation.fulfill()
    }

    client.send(EchoNotification(string: "hello!"))

    waitForExpectations(timeout: 10)
  }

  static var allTests = [
    ("testEcho", testEcho),
    ("testEchoError", testEchoError),
    ("testEchoNote", testEchoNote),
    ]
}

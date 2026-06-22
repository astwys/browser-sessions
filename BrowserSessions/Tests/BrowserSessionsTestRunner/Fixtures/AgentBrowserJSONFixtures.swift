enum AgentBrowserJSONFixtures {
    static let listTwoSessions = """
    {"success":true,"data":{"sessions":["alpha","beta"]}}
    """

    static let listEmpty = """
    {"success":true,"data":{"sessions":[]}}
    """

    static let closeSuccess = """
    {"success":true,"data":{"closed":true},"error":null}
    """

    static let malformed = "not json"

    static let urlResponse = """
    {"success":true,"data":{"url":"https://example.com"},"error":null}
    """
}

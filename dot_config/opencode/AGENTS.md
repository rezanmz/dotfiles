<!-- context7 -->
Use Context7 MCP for current documentation whenever the task asks about a library, framework, SDK, API, CLI tool, or cloud service. Prefer it over general web search because local model knowledge may be stale.

For a library question, first resolve the library ID, then query the specific concept needed. Keep separate concepts in separate queries. If Context7 is unavailable or authentication fails, stop retrying it and use an official documentation source or report the limitation.

When orchestrating without Context7 access, delegate library and API research to the librarian agent instead of repeatedly attempting the unavailable MCP.

Do not use Context7 for refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.
<!-- context7 -->

# Compose work and review flows

The Work Flow and Review Flow are independent modules joined by an immutable Change Set rather than one inseparable development procedure. Locally authored features normally compose Work Flow, Review Flow, Review Approval, and Squash Landing; reviewing externally authored code invokes the same read-only Review Flow and Agent Review Loop without creating or mutating a WIP Branch. This keeps review behavior uniform while avoiding false ownership of someone else's development history.

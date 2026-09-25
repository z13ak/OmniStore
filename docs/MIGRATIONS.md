# Migrations

Set a positive `schemaVersion` and provide migrations connecting every older supported version to
it. Each migration has `from`, `to`, and `migrate`, plus an optional `schema` describing the output
of that exact step.

```lua
migrations = {
    {
        from = 1,
        to = 2,
        schema = Version2Schema,
        migrate = function(data)
            data.Coins = data.Money or 0
            data.Money = nil
            return data
        end,
    },
    {
        from = 2,
        to = 3,
        migrate = function(data)
            data.Settings = data.Settings or { Music = true }
            return data
        end,
    },
}
```

Migrations run on decoded logical data while claiming the key and are committed with the lease
through the same atomic update. Every step must produce codec-encodable, serializable data; when a
step schema is provided it is validated immediately. After migration, template reconciliation and
the final store/model schema run before commit.

Rules:

- Treat the input as owned by the migration, but always return the resulting value.
- Do not yield, call DataStores, use randomness, or depend on mutable external state.
- Make transformations deterministic and safe if Roblox invokes the update callback again.
- Never edit a migration already used in production. Add a new version.
- Keep backups/export procedures outside this library and rehearse migrations with the memory
  adapter plus a separate test universe.
- A stored version newer than the configured version fails closed instead of downgrading.

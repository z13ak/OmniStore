# Schemas, models, and codecs

These features are optional. Plain templates and validation callbacks remain supported.

## Composable schemas

Schemas validate logical in-memory data and return path-aware failures:

```lua
local Schema = OmniStore.Schema

local ProfileSchema = Schema.object({
    Coins = Schema.number({ integer = true, min = 0 }),
    Inventory = Schema.array(Schema.object({
        Id = Schema.string({ minLength = 1, maxLength = 64 }),
        Equipped = Schema.boolean(),
    })),
    Nickname = Schema.optional(Schema.string({ maxLength = 20 })),
})
```

Objects reject undeclared fields by default. Set `{ allowUnknown = true }` only where forward
compatibility requires it. `Schema.custom` is for rules that cannot be expressed structurally; it
should be deterministic, non-yielding, and free of side effects.

## Model definitions

A model keeps the persistence contract together:

```lua
local ProfileModel = OmniStore.Model.define({
    typeId = "game.Profile",
    version = 3,
    schema = ProfileSchema,
    template = { Coins = 0, Inventory = {} },
    migrations = ProfileMigrations,
    codecs = codecs,
    allowLegacy = true,
})

local profiles = database:GetStore("Profiles", { model = ProfileModel })
```

Keep a model `typeId` stable when increasing `version`. It identifies the logical model, not a
specific schema version. A different stored type ID fails closed. `allowLegacy` controls adoption of
old untyped envelopes; it never permits adopting another model's ID.

## Codec registry

Codecs convert non-DataStore values into tagged serializable tables and decode them after load:

```lua
local codecs = OmniStore.CodecRegistry.new({ unknownTypePolicy = "Reject" })
OmniStore.Codecs.Roblox.registerAll(codecs)

codecs:Register({
    typeId = "game.ItemRef/v1",
    isType = function(value)
        return type(value) == "table" and getmetatable(value) == ItemRef
    end,
    encode = function(value)
        return { Id = value.Id }
    end,
    decode = function(payload)
        return ItemRef.new(payload.Id)
    end,
})
```

Codec IDs identify wire formats. Use a new ID when an incompatible encoding is introduced. Match,
encode, and decode callbacks can run inside an `UpdateAsync` transform, so they must not yield or
perform I/O and must be deterministic.

Encoded tags reserve the table shape `{ __omniCodec = 1, typeId = string, value = ... }`. Avoid using
that exact shape for ordinary game data. Duplicate IDs are rejected.

`Reject` fails on an unknown codec ID. `Preserve` retains the tagged serializable table unchanged so
a newer server can understand it later. Preservation does not make the value meaningful to the
current server, and a strict schema may still reject it.

## Validation order

On load, OmniStore validates the stored wire value, decodes codecs, runs and validates each migration
step, reconciles the template, then applies the final schema and callback validator. On save, it
validates logical data, encodes codecs, validates the encoded payload and full envelope, then writes
through the atomic adapter update.

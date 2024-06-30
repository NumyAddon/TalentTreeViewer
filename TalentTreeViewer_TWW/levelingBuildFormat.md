# The War Within Leveling Talent Build export string format

- Version: 2
- Date: June 2024
- Authoritative Source: [github.com/NumyAddon/TalentTreeViewer](https://github.com/NumyAddon/TalentTreeViewer/blob/master/TalentTreeViewer_TWW/levelingBuildFormat.md)

## Purpose
The purpose of the export string is to provide a way to save and share the order in which talents are learned while leveling.
A strong requirement is that the export string should be compatible with Blizzard's format and default in-game features.

## Format
The export string is built as follows:

`<TalentBuild>-LVL-<LevelingBuild>`
- `<TalentBuild>`: The talent build string, in Blizzard's format, without any modifications.
- `-LVL-`: A separator that indicates the start of the leveling build. This is case-sensitive.
- `<LevelingBuild>`: The leveling build string, in the format described below.

### Summary of differences from Version 1
- The header has been incremented to `2`
- The body still is a list of 7-bit integers, but the values now describe the level at which a given talent was learned

### Leveling Build Format
The leveling build string is a base64-encoded string, made of a sequence of of variable bit length integers.
The base64-encoding is done using Blizzard's modified base64 encoding. One can use their `ExportUtil` helper to read/write the string.

### Header
5 bits: `0b00010` - Header, describing the version of the format. 
Currently, this is `2`, any changes to the format, will increment the version, even if the changes are backwards compatible.

### Body
7 bits: The level at which a node entry rank was learned.

The body is a sequence of integers, which describe the level at which a talent was learned.
The integers are sorted by the order of `C_Traits.GetNodes`,
and filtered to only the talents that are _purchased_ in the `<TalentBuild>`, granted nodes are ignored.
Nodes that have multiple ranks purchased, will have the same number of sequential integers in the body,
indicating the level at which each rank was purchased.

A value of `0` indicates that the leveling build does not cover that specific level.
An example use-case is when the leveling build starts at e.g. level 50.
This also means that if the leveling build only covers e.g. spec talents, then every other value will be `0`.

A value of `10` indicates that the specific rank/entry was purchased at level 10.
Values below 10 are invalid, as talent trees unlock at level 10.
It is possible to have duplicate numbers in the body, indicating that multiple ranks were purchased at the same level.
This is only valid for Hero Spec trees however.
It is expected that the exporting party correctly handles this,
removing validation requirements from the importing party.

It's strongly recommended to avoid having talents with value `0`, which depend on a talent with a non-zero value. As this results in ambiguity.

The number of integers in the body must be equal to the number of talent ranks/entries selected in the `<TalentBuild>`, this includes the Hero Spec choice node.

#### Example
Let's say there are 4 talents learned in `<TalentBuild>`, A B C and D.
Talent A and C are class talents, and ignored by the leveling build, talent D is learned at level 11, and talent B is learned at level 13.

This results in a body with the following values (`_` is added for readability)
`0b000_0000 0b000_1101 0b000_0000 0b000_1011` (base10 `0 13 0 11`)

```lua
-- Given the above example, is parsed into tables as follows:
local talentsLearnedInTalentBuild = {"A", "B", "C", "D"};
local data = {0, 13, 0, 11};
-- The function below returns the talent learned at a specific level.
local function talentLearnedAtLevel(data, targetLevel)
    for i, level in ipairs(data) do
        if targetLevel == level then
            return i, talentsLearnedInTalentBuild[i];
        end
    end
end
print(talentLearnedAtLevel(data, 11)) -- 4, D
```
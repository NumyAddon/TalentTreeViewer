# Dragonflight Leveling Talent Build export string format

- Version: 1
- Date: April 2024

## Purpose
The purpose of the export string is to provide a way to save and share the order in which talents are learned while leveling.
A strong requirement is that the export string should be compatible with Blizzard's format and default in-game features.

## Format
The export string is built as follows:

`<TalentBuild>-LVL-<LevelingBuild>`
- `<TalentBuild>`: The talent build string, in Blizzard's format, without any modifications.
- `-LVL-`: A separator that indicates the start of the leveling build. This is case-sensitive.
- `<LevelingBuild>`: The leveling build string, in the format described below.

### Leveling Build Format
The leveling build string is a base64-encoded string, made of a sequence of of variable bit length integers.
The base64-encoding is done using Blizzard's modified base64 encoding. One can use their `ExportUtil` helper to read/write the string.

### Header
5 bits: `0b00001` - Header, describing the version of the format. 
Currently this is `1`, any changes to the format, will increment the version, even if the changes are backwards compatible.

### Body
7 bits: The 1-based index of the talent in a filtered `C_Traits.GetNodes` list.

The body is a sequence of integers, which describe the "purchasing order" of selected talents.
The integers are sorted by the order of `C_Traits.GetNodes`, and filtered to only the talents that are selected in the `<TalentBuild>`.
The list of integers, is effectively a pointer to the talent to be learned at each level.
The first value is the talent learned at level 10, the second value is the talent learned at level 11, and so on.

A value of `0` indicates that the leveling build does not cover that specific level.
For example, if the leveling build starts at level 50.
This also means that if the leveling build only covers e.g. spec talents, then every other value will be `0`.
Within a tree, it's invalid to have a value of `0` after a non-zero value, as it results in ambiguity.

A value of `1` indicates that the talent learned at that level is the first talent in the filtered `C_Traits.GetNodes` list. 

The number of integers in the body must be equal to the number of talents selected in the `<TalentBuild>`.

#### Example
Lets say there are 4 talents learned in `<TalentBuild>`, A B C and D.
Talent A and C are class talents, and ignored by the leveling build, talent D is learned at level 11, and talent C is learned at level 13.

This results in a body with the following values (`_` is added for readability) `0b000_0000 0b000_0100 0b000_0000 0b000_0011` (base10 `0 4 0 3`)

```lua
-- Given the above example, is parsed into tables as follows:
local talentsLearnedInTalentBuild = {"A", "B", "C", "D"};
local order = {0, 4, 0, 3};
-- The function below returns the talent learned at a specific level.
local function talentLearnedAtLevel(order, level)
    return order[level - 9], talentsLearnedInTalentBuild[order[level - 9]];
end
print(talentLearnedAtLevel(order, 11)) -- 4, D
```
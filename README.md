# Turtle Excavate & Fill Tool

A CC Tweaked turtle program that can excavate or fill any shape of area.

## Installation

On the turtle's terminal:

```
wget https://raw.githubusercontent.com/Tid0s19/turtle/master/turtle_tool.lua turtle_tool
```

Or use `pastebin` if the file is uploaded there:

```
pastebin get <CODE> turtle_tool
```

Then run:

```
turtle_tool
```

## Requirements

- CC Tweaked turtle (mining turtle recommended for excavate)
- A chest placed directly **behind** the turtle
- Fuel in slot 16 (or pre-fueled turtle)
- For custom shapes: CC Tweaked blocks (wired modem or network cable) for perimeter markers

## Physical Setup

### Excavate / Fill (Rectangle)

```
          length
   [C] [T->] --------+
        |   work area |  width
        +-------------+
```

- `[C]` = Chest (behind turtle)
- `[T->]` = Turtle (facing the work area)
- Place a CC Tweaked marker block at the opposite corner to auto-scan dimensions, or enter them manually.

### Excavate / Fill (Custom Shape)

```
   [C] [T->]
        |
     MMMMMM
    M      MMM
    M         M    <-- CC Tweaked blocks
    MM       M         (modem/cable) around
     MMMMMMMM         full perimeter
```

- Place CC Tweaked blocks (wired modem or network cable) around the **entire perimeter** of your desired shape.
- The shape can be anything: rectangle, L-shape, circle, irregular polygon, etc.
- The turtle will walk forward, find the perimeter, trace it, then work the interior.

## Modes

### Excavate

Digs everything inside the defined area down to a specified depth. Items are dumped into the chest behind the turtle. The turtle returns home when inventory is full, dumps, then continues.

### Fill

Fills gaps and holes in the defined area. At each column position:

1. Descends until hitting solid ground
2. Breaks plants, grass, flowers, wood, logs (replaceable blocks)
3. Breaks torches and returns them to the chest (collectible blocks)
4. Ascends back up, placing fill blocks at every empty position

Fill blocks are loaded from the chest behind the turtle. The turtle scans the chest first to learn which block types to use.

## Area Definition

### Rectangle Mode

Two options:

1. **Manual**: Enter length (forward) and width (right) directly.
2. **Scan**: Place a single CC Tweaked block at the opposite corner. The turtle scans forward to find the length, then scans right to find the width.

### Custom Shape Mode

1. Place CC Tweaked blocks (wired modem or network cable) around the **complete perimeter** of your shape.
2. The turtle walks forward until it hits the perimeter.
3. It traces the perimeter using wall-following (keeping markers on its right).
4. It records all marker positions and uses flood-fill to determine interior positions.
5. It then works all interior positions in a serpentine pattern.

This handles **any closed shape** of **any size**.

## Controls

- Main menu: `[1]` Excavate, `[2]` Fill, `[3]` Help
- Area mode: `[1]` Rectangle, `[2]` Custom Shape
- Pre-flight check: `[Y]` Start, `[N]` Cancel

## Fuel

- Keep fuel items in **slot 16**. The turtle will auto-refuel when low.
- A fuel warning appears if levels drop below 500.
- The pre-flight check shows estimated fuel needed for the job.

## Marker Blocks

The following CC Tweaked blocks are recognized as perimeter markers:

- `computercraft:wired_modem`
- `computercraft:wired_modem_full`
- `computercraft:cable`

These have zero chance of natural world generation, making them ideal markers.

## Tips

- For excavate, use a **mining turtle** (turtle + diamond pickaxe).
- For fill, load the chest with the blocks you want to fill with before starting.
- The turtle always returns to its starting position when done.
- Large areas will require significant fuel — bring plenty.
- The turtle uses slots 1-15 for items and slot 16 for fuel.

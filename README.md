[Status]
- Wind loss is working and applicable to all fill types, currently cars with tipper configurations are not working(CV, Tigre, etc.). Particles need refinement for multiple fill units per vehicle, currently they all emit from the last fill unit.

- Tilt loss is not implemented at this time

[Known Bugs]
- Fix particles emit for fillUnit > 1 per vehicle (they all share the last loaded shape node)
- Fix for cars/trucks that have configurations with fillUnit
- Investigate bug with changing systems where particles stop emitting
- Investigate bug with cleaning up particle effects when active and player/AI gets too far from the source causing them to not reappear when returning in view
- Investigate crash with a large amount of active windloss and particles

[TODO]
Future content:
- Implement tilt loss
- Implement tilt loss effects
 - initial findings suggest that it's impossible to use the grain effect seen with tipping trailers(uses a hardcoded effect in the vehicle i3d)
 - most likely case is just spawning a big smoke particle when loss is experienced
- Config menu

[Checklist]
- verify performance optimization is functional(distance, activity)
- verify that code is working is AI workers
- verify that working vehicles/implements experience loss
- verify liquids/slurry/milk/etc. does not experience loss

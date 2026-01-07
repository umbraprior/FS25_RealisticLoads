![mod-icon](icon_RealisticLoads.png)

# Realistic Loads
This script mod enhances the game by incentivizing the player to utilize the already in-game mechanics for trailered items. Loose goods and crops, like wheat or hay, will fall out of trailers when moving too quickly or tipped over unless covered. The current weather, speed, and mass of the goods can change the rate at which you lose your stuff. Be careful though, if the trailer tips over at too much of an angle or the weather gets too severe then the cover may break!

> [!WARNING]
> This mod is currently in an experimental state, bugs and problems may occur. If you experience any issues please report them by making a post.
> [here](https://github.com/umbraprior/FS25_RealisticLoads/issues/new)

## [Status]
- Wind loss is working and applicable to all fill types, currently cars with tipper configurations are not working(CV, Tigre, etc.). Particles need refinement for multiple fill units per vehicle, currently they all emit from the last fill unit.
- Tilt loss is not implemented at this time

## [Known Bugs]
1. Fix particles emit for fillUnit > 1 per vehicle (they all share the last loaded shape node)
2. Fix for cars/trucks that have configurations with fillUnit
3. Investigate bug with changing systems where particles stop emitting
4. Investigate bug with cleaning up particle effects when active and player/AI gets too far from the source causing them to not reappear when returning in view
5. Investigate crash with a large amount of active windloss and particles

### [TODO]
- [ ] Implement tilt loss
- [ ] Implement tilt loss effects
  - initial findings suggest that it's impossible to use the grain effect seen with tipping trailers(uses a hardcoded effect in the vehicle i3d)
  -  most likely case is just spawning a big smoke particle when loss is experienced
- [ ] Config menu

#### [v1.0 Release Checklist]
- [ ] verify performance optimization is functional(distance, activity)
- [ ] verify that code is working with AI workers
- [ ] verify that working vehicles/implements experience loss
- [ ] verify liquids/slurry/milk/etc. does not experience loss
- [ ] verify compatibility with modded vehicles, trailers, and fillTypes

--[[
    REALISTIC LOADS MOD - EFFECTS HANDLER
    =============================================================
    Handles all particle system and visual effects
]]

print("[RealisticLoads]: Effects handler file loading...");

-- Ensure RealisticLoads namespace exists
if RealisticLoads == nil then
    RealisticLoads = {};
end

-- Create Effects namespace
RealisticLoadsEffects = {};

-- Global template cache for wind smoke emitters
RealisticLoads._smokeParticleSystemRefs = nil;


-- Fill type color mapping (FALLBACK ONLY - colors are now retrieved dynamically)
-- RGB values from fillPlane diffuse textures, normalized to 0.0-1.0
-- Used as fallback if FillTypeManager.getSmokeColorByFillTypeIndex is not available
RealisticLoadsEffects.fillTypeColors = {
    -- Format: FILLTYPENAME = { r, g, b } where values are 0.0-1.0 (normalized from 0-255)
    BARLEY = { 139/255, 129/255, 101/255 },
    BARLEYCUT = { 146/255, 109/255, 54/255 },
    BEETROOT = { 140/255, 93/255, 80/255 },
    CANOLA = { 58/255, 51/255, 41/255 },
    CANOLACUT = { 142/255, 107/255, 69/255 },
    CARROT = { 158/255, 108/255, 57/255 },
    CHAFF = { 109/255, 112/255, 76/255 },
    COTTON = { 185/255, 181/255, 178/255 },
    FERTILIZER = { 196/255, 197/255, 197/255 },
    FORAGE = { 111/255, 96/255, 66/255 },
    GENERICSEED = { 146/255, 92/255, 50/255 },
    GRAPE = { 67/255, 93/255, 124/255 },
    GRASS = { 82/255, 86/255, 46/255 },
    GREENBEAN = { 132/255, 148/255, 82/255 },
    HAY = { 88/255, 84/255, 58/255 },
    IRONORE = { 146/255, 100/255, 75/255 },
    LIME = { 216/255, 214/255, 210/255 },
    LIQUIDMANURE = { 75/255, 63/255, 53/255 },
    MAIZE = { 187/255, 135/255, 70/255 },
    MANURE = { 100/255, 74/255, 40/255 },
    MINERALFEED = { 152/255, 118/255, 85/255 },
    OAT = { 168/255, 143/255, 97/255 },
    OATCUT = { 131/255, 104/255, 52/255 },
    OLIVE = { 125/255, 93/255, 54/255 },
    ONIONCLEAN = { 119/255, 84/255, 37/255 },
    ONIONDIRTY = { 120/255, 91/255, 54/255 },
    PARSNIP = { 128/255, 119/255, 106/255 },
    PEA = { 88/255, 120/255, 21/255 },
    PIGFOOD = { 128/255, 120/255, 84/255 },
    POPLAR = { 119/255, 114/255, 100/255 },
    POTATOES = { 117/255, 93/255, 66/255 },
    RICE = { 183/255, 165/255, 140/255 },
    RICELONGGRAIN = { 149/255, 140/255, 116/255 },
    ROADSALT = { 233/255, 233/255, 233/255 },
    SILAGE = { 50/255, 37/255, 21/255 },
    SNOW = { 208/255, 207/255, 207/255 },
    SORGHUM = { 141/255, 91/255, 56/255 },
    SOYBEAN = { 162/255, 140/255, 96/255 },
    SOYBEANCUT = { 119/255, 96/255, 43/255 },
    SPINACH = { 65/255, 85/255, 38/255 },
    STONE = { 109/255, 104/255, 94/255 },
    STRAW = { 140/255, 110/255, 63/255 },
    SUGARBEETS = { 119/255, 88/255, 62/255 },
    SUGARBEETSCUT = { 162/255, 131/255, 98/255 },
    SUGARCANE = { 107/255, 102/255, 59/255 },
    SUNFLOWER = { 78/255, 77/255, 75/255 },
    WHEAT = { 167/255, 126/255, 69/255 },
    WHEATCUT = { 144/255, 114/255, 62/255 },
    WOODCHIPS = { 113/255, 89/255, 76/255 },
    -- Windrow variants (use same colors as base types)
    DRYGRASS_WINDROW = { 88/255, 84/255, 58/255 }, -- Same as HAY
    GRASS_WINDROW = { 82/255, 86/255, 46/255 } -- Same as GRASS
};

--[[
    DYNAMIC PARTICLE PROPERTY CALCULATION
]]

-- Calculate particle properties (maxCount, lifespan) dynamically from fill type properties
-- This allows automatic support for any fill type (including modded ones) without hardcoding
function RealisticLoadsEffects.calculateParticleProperties(fillTypeProps)
    if fillTypeProps == nil then
        return { maxCount = 0, lifespan = 0 }; -- Unknown fill type, no wind loss
    end
    
    local massPerLiter = fillTypeProps.massPerLiter or RealisticLoads.STANDARD_MASS_PER_LITER;
    local firmness = fillTypeProps.firmness or 0.5;
    
    -- Heavier materials (higher massPerLiter) = fewer particles, shorter lifespan
    -- Lighter materials = more particles, longer lifespan
    -- Reference weight for calculations (0.0006 kg/L is average for grains)
    local referenceMass = 0.0006;
    
    -- Calculate maxCount based on mass (lighter = more particles)
    -- Range: Very heavy (0.002+) = 0-1 particles, Light (0.0003-) = 10-15 particles
    local massRatio = referenceMass / math.max(massPerLiter, 0.0001);
    local baseMaxCount = math.max(0, math.min(15, massRatio * 8));
    
    -- Adjust based on firmness (less firm = more particles can escape)
    -- Firmness 0.0-1.0: 0.0 = very loose (more particles), 1.0 = very firm (fewer particles)
    local firmnessMultiplier = 1.0 + (1.0 - firmness) * 1.5; -- Range: 1.0 to 2.5
    local calculatedMaxCount = math.floor(baseMaxCount * firmnessMultiplier);
    
    -- Cap maxCount: Very heavy materials (massPerLiter > 0.0015) should have 0 particles
    if massPerLiter > 0.0015 then
        calculatedMaxCount = 0;
    end
    
    -- Calculate lifespan based on mass (lighter particles stay in air longer)
    -- Range: Heavy materials = 300-500ms, Light materials = 800-1200ms
    local baseLifespan = 400 + (referenceMass / math.max(massPerLiter, 0.0001)) * 400;
    local calculatedLifespan = math.max(300, math.min(1200, baseLifespan));
    
    return {
        maxCount = calculatedMaxCount,
        lifespan = math.floor(calculatedLifespan)
    };
end

--[[
    PARTICLE SYSTEM LOADING
]]

-- Gets the smoke particle systems from ParticleSystemManager (already registered by the game)
-- Returns table with both 'smoke' and 'smoke_damping' particle systems
function RealisticLoadsEffects.loadSmokeParticleSystemReferences()
    print("[RealisticLoads]: loadSmokeParticleSystemReferences called");
    
    if RealisticLoads._smokeParticleSystemRefs ~= nil then
        print("[RealisticLoads]: Using cached smoke particle system references");
        return RealisticLoads._smokeParticleSystemRefs;
    end

    if g_particleSystemManager == nil then
        print("[RealisticLoads]: ERROR - g_particleSystemManager is nil");
        return nil;
    end

    print("[RealisticLoads]: g_particleSystemManager is available");
    
    local refs = {};
    
    -- Get the main smoke particle system
    if g_particleSystemManager.getParticleSystem ~= nil then
        print("[RealisticLoads]: Calling getParticleSystem('smoke')...");
        refs.smoke = g_particleSystemManager:getParticleSystem("smoke");
        print(string.format("[RealisticLoads]: getParticleSystem('smoke') returned: %s", tostring(refs.smoke)));
        
        -- Get the damping smoke particle system
        print("[RealisticLoads]: Calling getParticleSystem('smoke_damping')...");
        refs.smoke_damping = g_particleSystemManager:getParticleSystem("smoke_damping");
        print(string.format("[RealisticLoads]: getParticleSystem('smoke_damping') returned: %s", tostring(refs.smoke_damping)));
    else
        print("[RealisticLoads]: ERROR - getParticleSystem method not available");
        return nil;
    end

    if refs.smoke == nil then
        print("[RealisticLoads]: ERROR - Could not get smoke particle system from ParticleSystemManager");
        print("[RealisticLoads]: Attempting to list available particle types...");
        if g_particleSystemManager.particleTypes ~= nil then
            print(string.format("[RealisticLoads]: Available particle types: %s", table.concat(g_particleSystemManager.particleTypes, ", ")));
        end
        return nil;
    end

    if refs.smoke_damping == nil then
        print("[RealisticLoads]: WARNING - Could not get smoke_damping particle system (will only use main smoke system)");
    end

    -- Cache the references
    RealisticLoads._smokeParticleSystemRefs = refs;

    print("[RealisticLoads]: Successfully loaded smoke particle system references from ParticleSystemManager");

    return refs;
end

--[[
    PARTICLE SYSTEM CREATION
]]

-- Create a custom wind smoke particle system for a specific fill unit
function RealisticLoadsEffects.createWindSmokeEmitter(vehicle, fillUnitIndex)
    print(string.format("[RealisticLoads]: createWindSmokeEmitter called for fillUnit %d", fillUnitIndex));
    local spec = vehicle.spec_realisticLoads;
    local specFillUnit = vehicle.spec_fillUnit;

    if spec == nil or specFillUnit == nil then
        print(string.format("[RealisticLoads]: ERROR - createWindSmokeEmitter: spec or specFillUnit is nil (fillUnit %d)", fillUnitIndex));
        return nil;
    end

    -- Get this fill unit's exactFillRootNode
    local exactFillRootNode = specFillUnit:getFillUnitExactFillRootNode(fillUnitIndex);
    if exactFillRootNode == nil then
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: No exactFillRootNode for fillUnit %d, cannot create smoke particle system", fillUnitIndex));
        end
        return nil;
    end

    -- Load smoke particle system references (cached) - both smoke and smoke_damping
    local sourceParticleSystems = RealisticLoadsEffects.loadSmokeParticleSystemReferences();
    if sourceParticleSystems == nil or sourceParticleSystems.smoke == nil then
        print(string.format("[RealisticLoads]: ERROR - Failed to load smoke particle system reference for fillUnit %d", fillUnitIndex));
        return nil;
    end

    -- Get fill type BEFORE copying (needed for material application and to check if wind loss applies)
    local fillUnitFillType = specFillUnit:getFillUnitFillType(fillUnitIndex);
    
    -- Skip FUEL fill type (fuel tanks are enclosed, no wind loss)
    if fillUnitFillType ~= nil and fillUnitFillType ~= FillType.UNKNOWN and g_fillTypeManager ~= nil then
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillUnitFillType);
        if fillType ~= nil and fillType.name ~= nil and fillType.name == "FUEL" then
            if RealisticLoads.DEBUG_MODE then
                print(string.format("[RealisticLoads]: Fill type FUEL (index %d) excluded from wind loss, skipping particle system creation", fillUnitFillType));
            end
            return nil;
        end
    end
    
    -- Check if this fill type has wind loss enabled (maxCount > 0)
    local fillTypeName = "UNKNOWN";
    if fillUnitFillType ~= nil and fillUnitFillType ~= FillType.UNKNOWN and g_fillTypeManager ~= nil then
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillUnitFillType);
        if fillType ~= nil and fillType.name ~= nil then
            fillTypeName = fillType.name;
        end
    end
    
    -- Get fill type properties for dynamic calculation
    local fillTypeProps = RealisticLoadsCommon.getFillTypeProperties(fillUnitFillType);
    
    -- Calculate particle properties dynamically from fill type properties
    local particleProps = RealisticLoadsEffects.calculateParticleProperties(fillTypeProps);
    if RealisticLoads.DEBUG_MODE then
        print(string.format("[RealisticLoads]: Calculated particle properties for fill type %s: maxCount=%d, lifespan=%d", 
                fillTypeName, particleProps.maxCount, particleProps.lifespan));
    end
    local targetMaxCount = particleProps.maxCount or 0;
    
    -- If maxCount is 0, this fill type doesn't have wind loss (too heavy/dense)
    if targetMaxCount <= 0 then
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: Fill type %s (index %d) has no wind loss (maxCount=0), skipping particle system creation", fillTypeName, fillUnitFillType or 0));
        end
        return nil;
    end
    
    -- Copy the main smoke particle system
    local particleSystem = nil;
    if ParticleUtil ~= nil and ParticleUtil.copyParticleSystem ~= nil then
        particleSystem = ParticleUtil.copyParticleSystem(nil, nil, sourceParticleSystems.smoke, nil);
        if particleSystem == nil then
            print(string.format("[RealisticLoads]: ERROR - Failed to copy main smoke particle system for fillUnit %d", fillUnitIndex));
            return nil;
        end
    else
        print(string.format("[RealisticLoads]: ERROR - ParticleUtil.copyParticleSystem not available for fillUnit %d", fillUnitIndex));
        return nil;
    end

    -- Copy the damping smoke particle system (if available)
    local dampingParticleSystem = nil;
    if sourceParticleSystems.smoke_damping ~= nil and ParticleUtil ~= nil and ParticleUtil.copyParticleSystem ~= nil then
        dampingParticleSystem = ParticleUtil.copyParticleSystem(nil, nil, sourceParticleSystems.smoke_damping, nil);
        if dampingParticleSystem == nil then
            print(string.format("[RealisticLoads]: WARNING - Failed to copy damping smoke particle system for fillUnit %d (continuing without it)", fillUnitIndex));
        end
    end

    -- Link the emitterShape to exactFillRootNode and position it
    if particleSystem.emitterShape == nil then
        print(string.format("[RealisticLoads]: ERROR - Particle system missing emitterShape for fillUnit %d", fillUnitIndex));
        if ParticleUtil.deleteParticleSystem ~= nil then
            ParticleUtil.deleteParticleSystem(particleSystem);
        end
        return nil;
    end

    -- Unlink from any previous parent before linking to the correct exactFillRootNode
    -- This ensures each particle system stays at its own fill unit's location
    -- CRITICAL: Each fill unit MUST have its own independent particle system
    local previousParent = getParent(particleSystem.emitterShape);
    if previousParent ~= nil and previousParent ~= 0 then
        unlink(particleSystem.emitterShape);
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: Unlinked particle system emitterShape from previous parent for fillUnit %d", fillUnitIndex));
        end
    end
    link(exactFillRootNode, particleSystem.emitterShape);
    setVisibility(particleSystem.emitterShape, true);
    
    if RealisticLoads.DEBUG_MODE then
        print(string.format("[RealisticLoads]: Linked particle system for fillUnit %d to exactFillRootNode %d", fillUnitIndex, exactFillRootNode));
        print(string.format("[RealisticLoads]: Particle system emitterShape ID: %d, shape ID: %d, geometry ID: %d", 
                particleSystem.emitterShape, particleSystem.shape or 0, particleSystem.geometry or 0));
    end

    -- Link damping particle system to same node if it exists
    if dampingParticleSystem ~= nil and dampingParticleSystem.emitterShape ~= nil then
        -- Unlink damping particle system from any previous parent
        local dampingPreviousParent = getParent(dampingParticleSystem.emitterShape);
        if dampingPreviousParent ~= nil and dampingPreviousParent ~= 0 then
            unlink(dampingParticleSystem.emitterShape);
            if RealisticLoads.DEBUG_MODE then
                print(string.format("[RealisticLoads]: Unlinked damping particle system emitterShape from previous parent for fillUnit %d", fillUnitIndex));
            end
        end
        link(exactFillRootNode, dampingParticleSystem.emitterShape);
        setVisibility(dampingParticleSystem.emitterShape, true);
    end

    -- Diagnostic: Log particle system structure
    if RealisticLoads.DEBUG_MODE then
        print(string.format("[RealisticLoads]: Particle system structure for fillUnit %d:", fillUnitIndex));
        print(string.format("  - particleSystem.shape: %s", tostring(particleSystem.shape)));
        print(string.format("  - particleSystem.geometry: %s", tostring(particleSystem.geometry)));
        print(string.format("  - particleSystem.emitterShape: %s", tostring(particleSystem.emitterShape)));
        print(string.format("  - particleSystem.sizeScale (before): %s", tostring(particleSystem.sizeScale)));
        
        -- Check material on particle system shape
        if particleSystem.shape ~= nil and particleSystem.shape ~= 0 then
            local numMaterials = getNumOfMaterials(particleSystem.shape);
            print(string.format("  - particleSystem.shape numMaterials: %d", numMaterials));
            for i = 0, numMaterials - 1 do
                local material = getMaterial(particleSystem.shape, i);
                local slotName = getMaterialSlotName(particleSystem.shape, i);
                print(string.format("  - Material slot %d: material=%s, slotName=%s", i, tostring(material), tostring(slotName)));
            end
        end
    end
    
    -- fillUnitFillType and particleProps were already retrieved before copying
    local targetLifespan = particleProps.lifespan or 800;
    
    if RealisticLoads.DEBUG_MODE then
        print(string.format("  - FillType particle properties: name=%s, maxCount=%d, lifespan=%d", 
                fillTypeName, targetMaxCount, targetLifespan));
    end
    
    -- Helper function to set maxCount on a particle system
    local function setMaxCount(ps, prefix)
        if ps == nil then return end
        if ps.geometry ~= nil and ps.geometry ~= 0 then
            setMaxNumOfParticles(ps.geometry, targetMaxCount);
            if RealisticLoads.DEBUG_MODE then
                print(string.format("  - %s maxCount set to %d on geometry", prefix, targetMaxCount));
            end
        else
            if RealisticLoads.DEBUG_MODE then
                print(string.format("  - WARNING: %s particleSystem.geometry is invalid (nil or 0), cannot set maxCount", prefix));
            end
        end
    end
    
    -- Helper function to set lifespan on a particle system (if available)
    local function setLifespan(ps, prefix)
        if ps == nil then return end
        if ps.geometry ~= nil and ps.geometry ~= 0 then
            -- Set lifespan to flat value (keepBlendTimes=true to maintain blend timing)
            if setParticleSystemLifespan ~= nil then
                setParticleSystemLifespan(ps.geometry, targetLifespan, true);
                if RealisticLoads.DEBUG_MODE then
                    print(string.format("  - %s lifespan set to %d ms", prefix, targetLifespan));
                end
            end
        end
    end
    
    setMaxCount(particleSystem, "Main");
    setLifespan(particleSystem, "Main");
    if dampingParticleSystem ~= nil then
        setMaxCount(dampingParticleSystem, "Damping");
        setLifespan(dampingParticleSystem, "Damping");
    end
    
    -- Apply fill-type-specific color tinting using colorAlpha shader parameter
    -- This tints the smoke particles based on the fill type's smoke color
    -- Try to get smoke color from FillTypeManager first (dynamic, supports all fill types)
    local fillTypeColor = nil;
    if g_fillTypeManager ~= nil and g_fillTypeManager.getSmokeColorByFillTypeIndex ~= nil then
        local smokeColor = g_fillTypeManager:getSmokeColorByFillTypeIndex(fillUnitFillType, false);
        if smokeColor ~= nil then
            -- smokeColor is typically a table with r, g, b values (0.0-1.0 range)
            -- Convert to our format if needed
            if type(smokeColor) == "table" then
                fillTypeColor = { smokeColor[1] or smokeColor.r or 1.0, 
                                 smokeColor[2] or smokeColor.g or 1.0, 
                                 smokeColor[3] or smokeColor.b or 1.0 };
            end
        end
    end
    
    -- Fallback to hardcoded table if dynamic color not available
    if fillTypeColor == nil then
        fillTypeColor = RealisticLoadsEffects.fillTypeColors[fillTypeName];
    end
    
    -- Final fallback: neutral white (no tint)
    if fillTypeColor == nil then
        fillTypeColor = { 1.0, 1.0, 1.0 };
    end
    local function setColorAlpha(ps, prefix)
        if ps == nil or ps.shape == nil or ps.shape == 0 then return end
        -- colorAlpha is a float4 parameter: (r, g, b, alpha)
        -- RGB values are 0.0-1.0 (tint multiplier), alpha is 1.0 (preserve transparency)
        local r, g, b = fillTypeColor[1] or 1.0, fillTypeColor[2] or 1.0, fillTypeColor[3] or 1.0;
        local success, err = pcall(setShaderParameter, ps.shape, "colorAlpha", r, g, b, 1.0, false);
        if success then
            if RealisticLoads.DEBUG_MODE then
                print(string.format("  - Set colorAlpha=(%.3f, %.3f, %.3f, 1.0) on %s shape for fillType %s", r, g, b, prefix, fillTypeName));
            end
            return true;
        else
            if RealisticLoads.DEBUG_MODE then
                print(string.format("  - ERROR: Failed to set colorAlpha shader parameter on %s: %s", prefix, tostring(err)));
            end
        end
        return false;
    end
    
    setColorAlpha(particleSystem, "main");
    if dampingParticleSystem ~= nil then
        setColorAlpha(dampingParticleSystem, "damping");
    end

    -- Initially disable emission for both particle systems (will be enabled based on wind loss rate)
    if ParticleUtil ~= nil and ParticleUtil.setEmittingState ~= nil then
        ParticleUtil.setEmittingState(particleSystem, false);
        if RealisticLoads.DEBUG_MODE then
            print(string.format("  - Main smoke emission state: disabled"));
        end
        if dampingParticleSystem ~= nil then
            ParticleUtil.setEmittingState(dampingParticleSystem, false);
            if RealisticLoads.DEBUG_MODE then
                print(string.format("  - Damping smoke emission state: disabled"));
            end
        end
    end

    if RealisticLoads.DEBUG_MODE then
        print(string.format("[RealisticLoads]: Created smoke particle systems for fillUnit %d at exactFillRootNode", fillUnitIndex));
    end

    return {
        particleSystem = particleSystem,
        dampingParticleSystem = dampingParticleSystem,  -- May be nil if smoke_damping not available
        emitterShape = particleSystem.emitterShape,
        exactFillRootNode = exactFillRootNode,
        fillTypeId = fillUnitFillType  -- Store fill type used at creation (for detecting changes)
    };
end

--[[
    PARTICLE SYSTEM MANAGEMENT
]]

-- Cleanup particle system for a fill unit
function RealisticLoadsEffects.cleanupParticleSystem(fillUnitIndex, customEmitter)
    if customEmitter == nil then
        return;
    end
    
    print(string.format("[RealisticLoads]: Cleaning up smoke emitter for fillUnit %d", fillUnitIndex));
    
    -- Stop and delete main particle system
    if customEmitter.particleSystem ~= nil then
        if ParticleUtil ~= nil then
            if ParticleUtil.setEmittingState ~= nil then
                ParticleUtil.setEmittingState(customEmitter.particleSystem, false);
                print(string.format("[RealisticLoads]: Stopped main particle system emission (fillUnit %d)", fillUnitIndex));
            end
            if ParticleUtil.deleteParticleSystem ~= nil then
                ParticleUtil.deleteParticleSystem(customEmitter.particleSystem);
                print(string.format("[RealisticLoads]: Deleted main particle system (fillUnit %d)", fillUnitIndex));
            end
        end
    end
    
    -- Stop and delete damping particle system
    if customEmitter.dampingParticleSystem ~= nil then
        if ParticleUtil ~= nil then
            if ParticleUtil.setEmittingState ~= nil then
                ParticleUtil.setEmittingState(customEmitter.dampingParticleSystem, false);
                print(string.format("[RealisticLoads]: Stopped damping particle system emission (fillUnit %d)", fillUnitIndex));
            end
            if ParticleUtil.deleteParticleSystem ~= nil then
                ParticleUtil.deleteParticleSystem(customEmitter.dampingParticleSystem);
                print(string.format("[RealisticLoads]: Deleted damping particle system (fillUnit %d)", fillUnitIndex));
            end
        end
    end
    
    -- Delete emitter shape
    if customEmitter.emitterShape ~= nil then
        delete(customEmitter.emitterShape);
        print(string.format("[RealisticLoads]: Deleted emitter shape (fillUnit %d)", fillUnitIndex));
    end
end

-- Set particle system emission state and scale
function RealisticLoadsEffects.setParticleEmission(customEmitter, blowRate, fillUnitIndex)
    if customEmitter == nil or customEmitter.particleSystem == nil then
        return;
    end
    
    local particleSystem = customEmitter.particleSystem;
    local dampingParticleSystem = customEmitter.dampingParticleSystem;
    
    if blowRate > 0 then
        -- Set emission scale based on blow rate (scale 0-2.0 for visibility)
        local emissionScale = math.min(blowRate * 500.0, 2.0);  -- Scale blowRate to 0-2.0 range
        if ParticleUtil ~= nil and ParticleUtil.setEmitCountScale ~= nil then
            ParticleUtil.setEmitCountScale(particleSystem, emissionScale);
            if ParticleUtil.setEmittingState ~= nil then
                ParticleUtil.setEmittingState(particleSystem, true);
            end
            
            -- Also control damping particle system if it exists
            if dampingParticleSystem ~= nil then
                ParticleUtil.setEmitCountScale(dampingParticleSystem, emissionScale);
                if ParticleUtil.setEmittingState ~= nil then
                    ParticleUtil.setEmittingState(dampingParticleSystem, true);
                end
            end
        end
    else
        -- Disable emission for both particle systems
        if ParticleUtil ~= nil then
            if ParticleUtil.setEmitCountScale ~= nil then
                ParticleUtil.setEmitCountScale(particleSystem, 0);
            end
            if ParticleUtil.setEmittingState ~= nil then
                ParticleUtil.setEmittingState(particleSystem, false);
            end
            
            -- Also disable damping particle system if it exists
            if dampingParticleSystem ~= nil then
                if ParticleUtil.setEmitCountScale ~= nil then
                    ParticleUtil.setEmitCountScale(dampingParticleSystem, 0);
                end
                if ParticleUtil.setEmittingState ~= nil then
                    ParticleUtil.setEmittingState(dampingParticleSystem, false);
                end
            end
        end
    end
end

print("[RealisticLoads]: Effects handler file loaded successfully");


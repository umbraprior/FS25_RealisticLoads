--[[
    REALISTIC LOADS MOD - WIND LOSS SYSTEM
    =============================================================
    Handles all wind loss calculations and logic
]]

print("[RealisticLoads]: Wind loss system file loading...");

-- Ensure RealisticLoads namespace exists
if RealisticLoads == nil then
    RealisticLoads = {};
end

-- Create WindLoss namespace
RealisticLoadsWindLoss = {};

-- Verify dependencies
if RealisticLoadsCommon == nil then
    print("[RealisticLoads]: WARNING - RealisticLoadsCommon not found!");
end
if RealisticLoadsEffects == nil then
    print("[RealisticLoads]: WARNING - RealisticLoadsEffects not found!");
end


--[[
    SPEC FIELD INITIALIZATION
]]

-- Initialize wind loss spec fields
function RealisticLoadsWindLoss.initSpecFields(vehicle, spec)
    if vehicle == nil or spec == nil then
        return;
    end
    
    -- Initialize wind loss tracking
    spec.blowRatePerFillUnit = {};
    spec.timeSinceLastSync = {};
    spec.lastBlownVolume = {};
    spec.lastAirSpeed = nil;
    spec.windSmokeEmitters = {}; -- Track smoke particle systems for wind loss per fill unit
    spec.lastLoggedState = {}; -- For debug logging spam fix (tracked per fill unit)
    spec.lastFillLevel = {}; -- For fill type change detection optimization
end

--[[
    WIND SPEED CALCULATIONS
]]

-- Calculate current relative air speed (vehicle speed + wind speed)
function RealisticLoadsWindLoss.calculateCurrentRelativeAirSpeed(vehicle, spec)
    if vehicle == nil or spec == nil then
        return 0;
    end
    
    local vehicleSpeed = vehicle:getLastSpeed();
    spec.lastVehicleSpeed = vehicleSpeed or 0;
    local airSpeed = 0;
    
    if RealisticLoads.CONSIDER_WIND and g_currentMission.environment ~= nil and g_currentMission.environment.weather ~= nil then
        local windDirX, windDirZ, windVelocity = g_currentMission.environment.weather.windUpdater:getCurrentValues();
        local vehicleWorldDirection = {};
        vehicleWorldDirection.X, vehicleWorldDirection.Y, vehicleWorldDirection.Z = vehicle:getVehicleWorldDirection();
        
        if RealisticLoads.DEBUG_MODE and spec.debugInfo ~= nil then
            spec.debugInfo.windDirX = windDirX or 0;
            spec.debugInfo.windDirZ = windDirZ or 0;
            spec.debugInfo.windVelocity = windVelocity or 0;
            spec.debugInfo.vehicleWorldDirectionX = vehicleWorldDirection.X or 0;
            spec.debugInfo.vehicleWorldDirectionY = vehicleWorldDirection.Y or 0;
            spec.debugInfo.vehicleWorldDirectionZ = vehicleWorldDirection.Z or 0;
        end
        
        -- Calculate relative air speed (vector addition)
        airSpeed = math.sqrt(vehicleSpeed ^ 2 + windVelocity ^ 2 +
                2 * windVelocity * vehicleSpeed *
                        (vehicleWorldDirection.X * -windDirX + vehicleWorldDirection.Z * -windDirZ));
    else
        airSpeed = vehicleSpeed;
    end
    
    spec.lastAirSpeed = airSpeed;
    return airSpeed;
end

--[[
    BLOW RATE CALCULATIONS
]]

-- Calculate blow rates (for wind losses) - dynamically based on fill type properties
function RealisticLoadsWindLoss.calculateBlowRates(vehicle, airSpeed, fillUnits)
    local fillUnits = fillUnits or {};
    local specFillUnit = vehicle.spec_fillUnit;
    local blowRatePerFillUnit = {};
    
    if specFillUnit == nil then
        return blowRatePerFillUnit;
    end
    
    for fillUnitIndex, fillUnit in pairs(fillUnits) do
        local fillLevelPercent = specFillUnit:getFillUnitFillLevelPercentage(fillUnitIndex);
        local fillUnitFillType = specFillUnit:getFillUnitFillType(fillUnitIndex);
        
        if airSpeed < RealisticLoads.MIN_SPEED_TO_BLOW or fillUnitFillType == nil then
            blowRatePerFillUnit[fillUnitIndex] = 0;
        elseif RealisticLoads.fillTypesIndexToName[fillUnitFillType] == nil or fillLevelPercent == 0 then
            blowRatePerFillUnit[fillUnitIndex] = 0;
        elseif not RealisticLoadsCommon.isFillUnitExposed(vehicle, fillUnitIndex) then
            -- Covered or folded, no wind loss
            blowRatePerFillUnit[fillUnitIndex] = 0;
        else
            -- Get fill type properties dynamically
            local fillTypeProps = RealisticLoadsCommon.getFillTypeProperties(fillUnitFillType);
            local fillTypeName = fillTypeProps.name;
            
            -- Calculate blow rate based on fill type properties
            -- Heavier materials (higher massPerLiter) are less affected by wind
            local blowVolumeFactor = fillLevelPercent ^ 3; -- Cubic relationship with fill level
            
            -- Calculate base blow factor from fill type properties
            -- Heavier materials naturally resist wind more
            local referenceWeight = 0.001; -- Reference weight for calculations
            local baseWeightFactor = referenceWeight / math.max(fillTypeProps.massPerLiter, 0.0001);
            
            -- Firmness factor: Lower firmness = higher wind loss (less resistance to wind)
            -- Invert firmness: 1.0 = firm (resists wind), 0.0 = loose (blows away easily)
            local firmnessFactor = 1.5 - (fillTypeProps.firmness * 1.0); -- Range: 0.5 to 1.5 (inverted)
            
            -- Calculate base blow factor from physical properties
            local finalBlowFactor = RealisticLoads.STANDARD_BLOW_FACTOR * baseWeightFactor * firmnessFactor;
            
            -- Cap to prevent extreme values
            finalBlowFactor = math.max(0.01, math.min(finalBlowFactor, 5.0));
            
            -- Calculate blow rate based on final blow factor
            -- The blow factor already accounts for weight and firmness, so we use it directly
            -- Blow rate in liters per second: factor * (speed difference)^2 / scaling_factor
            local speedDiff = math.max(0, airSpeed - RealisticLoads.MIN_SPEED_TO_BLOW);
            local blowRate = finalBlowFactor * (speedDiff * speedDiff) / 1000;
            blowRatePerFillUnit[fillUnitIndex] = blowVolumeFactor * blowRate * RealisticLoads.BLOW_FACTOR_GLOBAL;
        end
    end
    
    return blowRatePerFillUnit;
end

--[[
    WIND LOSS APPLICATION
]]

-- Remove material from fill unit due to wind loss
function RealisticLoadsWindLoss.blowFromFillUnit(vehicle, fillUnitIndex, newVol, sendNoEvent, unloadInfo)
    local spec = vehicle.spec_realisticLoads;
    local specFillUnit = vehicle.spec_fillUnit;

    -- Pass nil for unloadInfo since we're not updating the terrain
    local appliedDelta = specFillUnit:addFillUnitFillLevel(
            vehicle:getOwnerFarmId(),
            fillUnitIndex,
            newVol - specFillUnit:getFillUnitFillLevel(fillUnitIndex),
            specFillUnit:getFillUnitFillType(fillUnitIndex),
            ToolType.UNDEFINED,
            nil
    );

    vehicle:updateMass();

    if not sendNoEvent then
        RealisticLoadsWindEvent.sendEvent(vehicle, fillUnitIndex, newVol, sendNoEvent);
    end
end

--[[
    PARTICLE SYSTEM MANAGEMENT
]]

-- Check if fill type changed and recreate particle system if needed
-- Only checks when fill level transitions
function RealisticLoadsWindLoss.checkFillTypeChange(vehicle, spec, fillUnitIndex, fillUnitFillType, currentFillLevel, specFillUnit)
    local customEmitter = spec.windSmokeEmitters[fillUnitIndex];
    if customEmitter == nil then
        return false; -- No emitter exists, need to create one
    end
    
    -- Only check fill type change on fill level transitions
    local lastFillLevel = spec.lastFillLevel[fillUnitIndex] or 0;
    local fillLevelThreshold = 0.01; -- 1% threshold
    
    local wasEmpty = (lastFillLevel <= fillLevelThreshold);
    local isEmpty = (currentFillLevel <= fillLevelThreshold);
    local fillLevelTransitioned = (wasEmpty ~= isEmpty);
    
    -- Only check fill type change if fill level transitioned (empty to filled or filled to empty)
    if not fillLevelTransitioned then
        -- Update last fill level and return (no change detected)
        spec.lastFillLevel[fillUnitIndex] = currentFillLevel;
        return false;
    end
    
    -- Fill level transitioned, check if fill type changed
    local oldFillTypeId = customEmitter.fillTypeId;
    if oldFillTypeId ~= fillUnitFillType then
        -- Fill type changed - delete old particle systems and recreate
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: Fill type changed for fillUnit %d, cleaning up old particle system (old: %d, new: %d)", 
                    fillUnitIndex, oldFillTypeId or 0, fillUnitFillType or 0));
        end
        
        if RealisticLoadsEffects ~= nil then
            RealisticLoadsEffects.cleanupParticleSystem(fillUnitIndex, customEmitter);
        end
        
        spec.windSmokeEmitters[fillUnitIndex] = nil;
        spec.lastFillLevel[fillUnitIndex] = currentFillLevel;
        return true; -- Fill type changed, need to recreate
    end
    
    -- Update last fill level
    spec.lastFillLevel[fillUnitIndex] = currentFillLevel;
    return false;
end

-- Create or get particle system for fill unit
-- Create proactively for all exposed fill units with material, not just when blowRate > 0
function RealisticLoadsWindLoss.getOrCreateParticleSystem(vehicle, spec, fillUnitIndex, fillUnitFillType, isExposed, fillLevel, specFillUnit)
    -- Get current fill level for transition detection
    local currentFillLevel = fillLevel or 0;
    if specFillUnit ~= nil then
        currentFillLevel = specFillUnit:getFillUnitFillLevelPercentage(fillUnitIndex) or 0;
    end
    
    -- Check if particle system already exists and fill type hasn't changed
    local fillTypeChanged = RealisticLoadsWindLoss.checkFillTypeChange(vehicle, spec, fillUnitIndex, fillUnitFillType, currentFillLevel, specFillUnit);
    
    -- Create particle system if it doesn't exist or fill type changed
    -- Create proactively for all exposed fill units with material
    if spec.windSmokeEmitters[fillUnitIndex] == nil then
        -- Only create if exposed and has material (proactive creation)
        if vehicle.isClient and isExposed and currentFillLevel > 0.01 and fillUnitFillType and fillUnitFillType ~= FillType.UNKNOWN then
            if RealisticLoadsEffects ~= nil and RealisticLoadsEffects.createWindSmokeEmitter ~= nil then
                local success, customEmitter = pcall(function()
                    return RealisticLoadsEffects.createWindSmokeEmitter(vehicle, fillUnitIndex);
                end);
                
                if success and customEmitter ~= nil then
                    if customEmitter.particleSystem == nil then
                        if RealisticLoads.DEBUG_MODE then
                            print(string.format("[RealisticLoads]: ERROR - Custom emitter missing particleSystem for fillUnit %d", fillUnitIndex));
                        end
                    else
                        spec.windSmokeEmitters[fillUnitIndex] = customEmitter;
                        if RealisticLoads.DEBUG_MODE then
                            print(string.format("[RealisticLoads]: Created smoke particle system for fillUnit %d", fillUnitIndex));
                        end
                    end
                elseif RealisticLoads.DEBUG_MODE then
                    print(string.format("[RealisticLoads]: WARNING - Could not create custom smoke emitter for fillUnit %d", fillUnitIndex));
                end
            end
        end
    end
    
    return spec.windSmokeEmitters[fillUnitIndex];
end

--[[
    MAIN WIND LOSS LOGIC
]]

-- Apply wind losses to fill units
function RealisticLoadsWindLoss.affectFillUnits(vehicle, spec, dt)
    if vehicle == nil or spec == nil then
        return;
    end
    
    if not RealisticLoads.ENABLE_WIND_LOSS then
        return;
    end
    
    local specFillUnit = vehicle.spec_fillUnit;
    if specFillUnit == nil then
        return;
    end
    
    -- Skip wind loss if vehicle is stationary
    local vehicleSpeed = spec.lastVehicleSpeed or 0;
    if vehicleSpeed < 1.0 then
        -- Stop all particle emissions and return
        RealisticLoadsWindLoss.stopAllSmokeEmitters(spec);
        return;
    end
    
    -- Calculate relative air speed
    local airSpeed = RealisticLoadsWindLoss.calculateCurrentRelativeAirSpeed(vehicle, spec);
    
    -- Calculate blow rates
    local blowRatePerFillUnit = RealisticLoadsWindLoss.calculateBlowRates(vehicle, airSpeed, spec.supportedFillUnits);
    spec.blowRatePerFillUnit = blowRatePerFillUnit;
    
    -- Process each fill unit
    for fillUnitIndex, fillUnit in pairs(spec.supportedFillUnits) do
        local fillLevel = specFillUnit:getFillUnitFillLevelPercentage(fillUnitIndex);
        local fillLevelAbsolute = specFillUnit:getFillUnitFillLevel(fillUnitIndex);
        local fillUnitFillType = specFillUnit:getFillUnitFillType(fillUnitIndex);
        local isExposed = RealisticLoadsCommon.isFillUnitExposed(vehicle, fillUnitIndex);
        local blowRate = blowRatePerFillUnit[fillUnitIndex] or 0;
        
        -- Skip logging if fill unit is empty
        if fillLevelAbsolute <= 0.01 then
            -- Clear last logged state when empty
            if spec.lastLoggedState[fillUnitIndex] ~= nil then
                spec.lastLoggedState[fillUnitIndex] = nil;
            end
            -- Skip empty fill units for particle system creation and processing
            if spec.windSmokeEmitters[fillUnitIndex] ~= nil then
                -- Stop and cleanup particle system if it exists
                if RealisticLoadsEffects ~= nil then
                    RealisticLoadsEffects.setParticleEmission(spec.windSmokeEmitters[fillUnitIndex], 0, fillUnitIndex);
                end
            end
        else
            -- Fill unit has material - get or create particle system proactively
            if vehicle.isClient then
                local customEmitter = RealisticLoadsWindLoss.getOrCreateParticleSystem(vehicle, spec, fillUnitIndex, fillUnitFillType, isExposed, fillLevel, specFillUnit);
                
                -- Control particle emission based on exposure and blow rate
                if customEmitter ~= nil then
                    if not isExposed or blowRate <= 0 then
                        -- Stop emission when not exposed or no blow rate
                        if RealisticLoadsEffects ~= nil then
                            RealisticLoadsEffects.setParticleEmission(customEmitter, 0, fillUnitIndex);
                        end
                    end
                end
            end
        end
        
        -- Apply wind losses if exposed and blow rate > 0
        if isExposed and (blowRate > 0 or (spec.lastBlownVolume[fillUnitIndex] or 0) > 0) then
            -- Accumulate volume loss over time
            -- blowRatePerFillUnit is in liters per second, dt is in milliseconds
            local deltaVol = blowRate * dt / 1000;
            spec.lastBlownVolume[fillUnitIndex] = (spec.lastBlownVolume[fillUnitIndex] or 0) + deltaVol;
            spec.timeSinceLastSync[fillUnitIndex] = (spec.timeSinceLastSync[fillUnitIndex] or 0) + dt;
            
            -- Control particle emission based on blow rate
            if vehicle.isClient then
                local customEmitter = spec.windSmokeEmitters[fillUnitIndex];
                if customEmitter ~= nil and RealisticLoadsEffects ~= nil then
                    RealisticLoadsEffects.setParticleEmission(customEmitter, blowRate, fillUnitIndex);
                end
            end
            
            -- Apply accumulated volume loss periodically
            if spec.timeSinceLastSync[fillUnitIndex] > RealisticLoads.SYNC_TIME_INTERVAL_MS then
                local currentFillLevel = specFillUnit:getFillUnitFillLevel(fillUnitIndex);
                local lostVolume = spec.lastBlownVolume[fillUnitIndex];
                local newFillLevel = math.max(0, currentFillLevel - lostVolume);

                -- Debug: Log wind loss calculation details (only on state changes to reduce spam)
                if RealisticLoads.DEBUG_MODE then
                    local lastState = spec.lastLoggedState[fillUnitIndex] or {};
                    local stateChanged = (
                        (lastState.isExposed ~= isExposed) or
                        (lastState.hasMaterial ~= (fillLevel > 0.01)) or
                        (math.abs((lastState.blowRate or 0) - blowRate) > 0.001) or
                        (math.abs((lastState.fillLevel or 0) - fillLevel) > 0.05) or
                        (lostVolume > 0) -- Always log when material is lost
                    );
                    
                    if stateChanged then
                        local vehicleName = "UNKNOWN";
                        if Vehicle ~= nil and Vehicle.getFullName ~= nil then
                            vehicleName = Vehicle.getFullName(vehicle) or "UNKNOWN";
                        end
                        print(string.format("[RealisticLoads]: WIND LOSS - Vehicle: %s, FillUnit: %d, Exposed: %s, FillLevel: %.1f%%, BlowRate: %.6f, LostVol: %.6f L",
                                vehicleName, fillUnitIndex, tostring(isExposed), fillLevel * 100, blowRate, lostVolume));
                        spec.lastLoggedState[fillUnitIndex] = {
                            isExposed = isExposed,
                            hasMaterial = (fillLevel > 0.01),
                            blowRate = blowRate,
                            fillLevel = fillLevel
                        };
                    end
                end

                -- Apply wind loss
                if lostVolume > 0 then
                    RealisticLoadsWindLoss.blowFromFillUnit(vehicle, fillUnitIndex, newFillLevel, false, nil);
                end
                
                -- Reset accumulation
                spec.lastBlownVolume[fillUnitIndex] = 0;
                spec.timeSinceLastSync[fillUnitIndex] = 0;
            end
        else
            -- No active wind loss - reset accumulated volume when not exposed
            spec.lastBlownVolume[fillUnitIndex] = 0;
            spec.timeSinceLastSync[fillUnitIndex] = 0;
        end
    end
end

--[[
    PARTICLE SYSTEM CONTROL
]]

-- Stop all smoke emitters (used when vehicle becomes inactive)
function RealisticLoadsWindLoss.stopAllSmokeEmitters(spec)
    if spec == nil or spec.windSmokeEmitters == nil then
        return;
    end
    
    for fillUnitIndex, customEmitter in pairs(spec.windSmokeEmitters) do
        if customEmitter ~= nil and RealisticLoadsEffects ~= nil then
            RealisticLoadsEffects.setParticleEmission(customEmitter, 0, fillUnitIndex);
        end
    end
end

--[[
    CLEANUP
]]

-- Cleanup wind loss on delete
function RealisticLoadsWindLoss.onDelete(vehicle, spec)
    if vehicle == nil or spec == nil then
        return;
    end
    
    -- Cleanup smoke particle systems for wind loss
    if spec.windSmokeEmitters ~= nil then
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: onDelete - Cleaning up %d smoke emitter(s)", table.getn(spec.windSmokeEmitters) or 0));
        end
        
        for fillUnitIndex, customEmitter in pairs(spec.windSmokeEmitters) do
            if customEmitter ~= nil and RealisticLoadsEffects ~= nil then
                RealisticLoadsEffects.cleanupParticleSystem(fillUnitIndex, customEmitter);
            end
        end
        
        spec.windSmokeEmitters = nil;
        if RealisticLoads.DEBUG_MODE then
            print(string.format("[RealisticLoads]: onDelete - Cleanup complete, windSmokeEmitters set to nil"));
        end
    end
end

print("[RealisticLoads]: Wind loss system file loaded successfully");


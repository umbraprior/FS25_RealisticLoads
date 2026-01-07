print("[RealisticLoads]: WIND EVENT FILE LOADING - LINE 1");

--[[
    REALISTIC LOADS MOD - WIND LOSS EVENT
    =============================================================
]]

print("[RealisticLoads]: Loading RealisticLoadsWindEvent.lua");

RealisticLoadsWindEvent = {};
local RealisticLoadsWindEvent_mt = Class(RealisticLoadsWindEvent, Event);
InitEventClass(RealisticLoadsWindEvent, "RealisticLoadsWindEvent");

function RealisticLoadsWindEvent.emptyNew()
    local self = Event.new(RealisticLoadsWindEvent_mt);
    return self;
end

function RealisticLoadsWindEvent.new(vehicle, fillUnitIndex, newVol)
    local self = RealisticLoadsWindEvent.emptyNew();
    self.vehicle = vehicle;
    self.fillUnitIndex = fillUnitIndex;
    self.newVol = newVol;
    return self;
end

function RealisticLoadsWindEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId);
    self.fillUnitIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS);
    self.newVol = streamReadFloat32(streamId);
    self:run(connection);
end

function RealisticLoadsWindEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle);
    streamWriteUIntN(streamId, self.fillUnitIndex, FillTypeManager.SEND_NUM_BITS);
    streamWriteFloat32(streamId, self.newVol);
end

function RealisticLoadsWindEvent:run(connection)
    if not connection:getIsServer() then
        if RealisticLoadsWindLoss ~= nil and RealisticLoadsWindLoss.blowFromFillUnit ~= nil then
            RealisticLoadsWindLoss.blowFromFillUnit(self.vehicle, self.fillUnitIndex, self.newVol, true, nil);
        end
        g_server:broadcastEvent(self, false, connection, self.vehicle);
    else
        if RealisticLoadsWindLoss ~= nil and RealisticLoadsWindLoss.blowFromFillUnit ~= nil then
            RealisticLoadsWindLoss.blowFromFillUnit(self.vehicle, self.fillUnitIndex, self.newVol, true, nil);
        end
    end
end

function RealisticLoadsWindEvent.sendEvent(vehicle, fillUnitIndex, newVol, noEventSend)
    if noEventSend == nil or not noEventSend then
        if g_server ~= nil then
            g_server:broadcastEvent(RealisticLoadsWindEvent.new(vehicle, fillUnitIndex, newVol), nil, nil, vehicle);
        else
            g_client:getServerConnection():sendEvent(RealisticLoadsWindEvent.new(vehicle, fillUnitIndex, newVol));
        end
    end
end


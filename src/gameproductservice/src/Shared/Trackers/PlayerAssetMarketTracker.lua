--[=[
	Tracks a single asset type for pending purchase prompts.

	@class PlayerAssetMarketTracker
]=]

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")
local Signal = require("Signal")
local Promise = require("Promise")

local PlayerAssetMarketTracker = setmetatable({}, BaseObject)
PlayerAssetMarketTracker.ClassName = "PlayerAssetMarketTracker"
PlayerAssetMarketTracker.__index = PlayerAssetMarketTracker

function PlayerAssetMarketTracker.new(assetType, convertIds)
	local self = setmetatable(BaseObject.new(), PlayerAssetMarketTracker)

	self._assetType = assert(assetType, "No assetType")
	self._convertIds = assert(convertIds, "No convertIds")

	self._pendingPromises = {} -- { [number] = Promise<boolean> }
	self._purchasedThisSession = {} -- [number] = true
	self._receiptProcessingExpected = false

	self._promptsOpen = Instance.new("IntValue")
	self._promptsOpen.Value = 0
	self._maid:GiveTask(self._promptsOpen)

	self.Purchased = Signal.new() -- :Fire(id)
	self._maid:GiveTask(self.Purchased)

	self.PromptFinished = Signal.new() -- :Fire(id, isPurchased)
	self._maid:GiveTask(self.PromptFinished)

	self.ShowPromptRequested = Signal.new() -- :Fire(id)
	self._maid:GiveTask(self.ShowPromptRequested)

	self._maid:GiveTask(function()
		while #self._purchasedThisSession > 0 do
			local pending = table.remove(self._purchasedThisSession, #self._purchasedThisSession)
			pending:Reject()
		end
	end)

	return self
end

--[=[
	Prompts the player to purchase a the asset and returns a tracking promise which
	will resolve with the purchase state

	@param idOrKey number | string
	@return Promise<boolean>
]=]
function PlayerAssetMarketTracker:PromisePromptPurchase(idOrKey)
	assert(type(idOrKey) == "number" or type(idOrKey) == "string", "Bad idOrKey")

	local id = self._convertIds(idOrKey)
	if not id then
		return Promise.rejected(("No %s with key %q"):format(self._assetType, tostring(idOrKey)))
	end

	if self._pendingPromises[id] then
		return self._maid:GivePromise(self._pendingPromises[id])
	end

	local ownershipPromise
	if self._ownershipTracker then
		ownershipPromise = self._ownershipTracker:PromiseOwnsAsset(id)
	else
		ownershipPromise = Promise.resolved(false)
	end

	return ownershipPromise:Then(function(ownsAsset)
		if ownsAsset then
			return true
		end

		local promise = Promise.new()
		self._pendingPromises[id] = promise

		self._promptsOpen.Value = self._promptsOpen.Value + 1

		promise:Finally(function()
			self._promptsOpen.Value = self._promptsOpen.Value - 1
		end)

		self.ShowPromptRequested:Fire(id)

		return self._maid:GivePromise(promise)
	end)
end

function PlayerAssetMarketTracker:SetOwnershipTracker(ownershipTracker)
	assert(type(ownershipTracker) == "table" or ownershipTracker == nil, "Bad ownershipTracker")

	self._ownershipTracker = ownershipTracker
end

--[=[
	Returns true if item has been purchased this session

	@param idOrKey string | number
	@return boolean
]=]
function PlayerAssetMarketTracker:HasPurchasedThisSession(idOrKey)
	assert(type(idOrKey) == "number" or type(idOrKey) == "string", "idOrKey")

	local id = self._convertIds(idOrKey)
	if not id then
		warn(("[PlayerAssetMarketTracker] - No %s with key %q"):format(self._assetType, tostring(idOrKey)))
		return false
	end

	if self._purchasedThisSession[id] then
		return true
	end

	return false
end

function PlayerAssetMarketTracker:IsPromptOpen()
	return self._promptsOpen.Value > 0
end

--[=[
	Handles a purchasing event resolving any promises as needed

	@param id number
	@param isPurchased boolean
]=]
function PlayerAssetMarketTracker:HandlePurchaseEvent(id, isPurchased)
	assert(type(id) == "number", "Bad id")
	assert(type(isPurchased) == "boolean", "Bad isPurchased")

	self:_handlePurchaseEvent(id, isPurchased, false)
end

function PlayerAssetMarketTracker:_handlePurchaseEvent(id, isPurchased, isFromReceipt)
	assert(type(id) == "number", "Bad id")
	assert(type(isPurchased) == "boolean", "Bad isPurchased")

	local promise = self._pendingPromises[id]

	-- Zero out promise resolution in receipt processing scenario (safety)
	if self._receiptProcessingExpected then
		if isPurchased and not isFromReceipt then
			promise = nil
		end
	end

	if promise then
		self._pendingPromises[id] = nil
	end

	if isPurchased then
		self._purchasedThisSession[id] = true
		self.Purchased:Fire(id)
	end

	self.PromptFinished:Fire(id, isPurchased)

	if promise then
		task.spawn(function()
			promise:Resolve(isPurchased)
		end)
	end
end

function PlayerAssetMarketTracker:SetReceiptProcessingExpected(receiptProcessingExpected)
	assert(type(receiptProcessingExpected) == "boolean", "Bad receiptProcessingExpected")

	self._receiptProcessingExpected = receiptProcessingExpected
end

function PlayerAssetMarketTracker:HandleProcessReceipt(_player, receiptInfo)
	assert(self._receiptProcessingExpected, "No receiptProcessingExpected")

	local productId = receiptInfo.ProductId
	local pendingForAssetId = self._pendingPromises[productId]

	if pendingForAssetId then
		self:_handlePurchaseEvent(productId, true, true)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Always grant...
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return PlayerAssetMarketTracker
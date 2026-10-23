--[[

Author: yxllxwsrollin
Description:

BufferSerializer allows for you to handle buffers more effectively by writing and reading values to a buffer,
while removing the complexity from it. The buffer grows automatically as you write, so the size you pass
to new() is only a starting point.

Example Usage:

	local serializer = BufferSerializer.new() -- Starts at 64 bytes and grows as needed
	serializer:WriteString("Hello, world!")
	serializer:WriteUInt8(255)
	serializer:WriteInt32(-12345)
	serializer:WriteFloat32(3.14159)
	serializer:WriteBools(true, false, true) -- 3 booleans packed into 1 byte
	serializer:WriteQuantizedFloat(73.5, 0, 100) -- 2 bytes instead of 4
	serializer:WriteVector3(Vector3.new(1, 2, 3))
	serializer:WriteColor3(Color3.fromRGB(255, 128, 0))
	serializer:WriteCFrameCompact(CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(90), 0))
	serializer:WriteEnum(Enum.Material.Grass)
	serializer:WriteArray({ 10, 20, 30 }, serializer.WriteUInt16)

	local buf = serializer:ToBuffer() -- Trimmed to exactly the bytes written

	-- Now you can send the buffer over the network or store it as needed
	local reader = BufferSerializer.fromBuffer(buf)
	local message = reader:ReadString()
	local number = reader:ReadUInt8()
	local negative = reader:ReadInt32()
	local pi = reader:ReadFloat32()
	local a, b, c = reader:ReadBools(3)
	local health = reader:ReadQuantizedFloat(0, 100)
	local vector = reader:ReadVector3()
	local colour = reader:ReadColor3()
	local cf = reader:ReadCFrameCompact()
	local material = reader:ReadEnum(Enum.Material)
	local list = reader:ReadArray(reader.ReadUInt16)
	print(message, number, negative, pi, a, b, c, health, vector, colour, cf, material, list)

Patch Notes:

	16/9/26:
		BREAKING: Strings now use a VarUInt length prefix, so strings longer than 255 bytes work.
			Data written by older versions will not read correctly with this version.
		The buffer now grows automatically when writing past its end.
		new() size is now optional (defaults to 64).
		Added ToBuffer() which returns a copy trimmed to the bytes written.
		Added WriteUInt32/ReadUInt32 and signed Int8/Int16/Int32 functions.
		Added WriteBool/ReadBool and WriteBools/ReadBools (up to 8 booleans in one byte).
		Added WriteVarUInt/ReadVarUInt (1-5 bytes depending on size).
		Added WriteQuantizedFloat/ReadQuantizedFloat (a ranged float in 2 bytes).
		Added WriteBuffer and ReadBuffer functions.
		Added Vector2, Vector3int16, Color3, UDim, UDim2 and EnumItem support.
		Added WriteCFrameCompact/ReadCFrameCompact (28 bytes instead of 48).
		Added WriteArray/ReadArray helpers.
		Added GetCursor, SetCursor, Skip, Remaining, GetSize and Peek.
		Added an exported BufferSerializer type.

	19/8/26:
		Added WriteCFrame and ReadCFrame functions.

	15/8/26:
		Added Float64 Support.

	20/7/26:
		BufferSerializer now has a Reset() function to reset the cursor.
		Added WriteString and ReadString functions.
		Added WriteVector3 and ReadVector3 functions.
		Added WriteFloat32 and ReadFloat32 functions.
		Added WriteUInt16 and ReadUInt16 functions.
		Added WriteUInt8 and ReadUInt8 functions.

Copyright 2026 Yxllxws

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

]]--

local DEFAULT_SIZE = 64

local BufferSerializer = {}
BufferSerializer.__index = BufferSerializer

type SerializerData = {
	buffer: buffer,
	cursor: number,
}

export type BufferSerializer = typeof(setmetatable({} :: SerializerData, BufferSerializer))

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function BufferSerializer.new(size: number?): BufferSerializer
	local self = setmetatable({} :: SerializerData, BufferSerializer)
	self.buffer = buffer.create(math.max(size or DEFAULT_SIZE, 1))
	self.cursor = 0
	return self
end

function BufferSerializer.fromBuffer(existingBuffer: buffer): BufferSerializer
	local self = setmetatable({} :: SerializerData, BufferSerializer)
	self.buffer = existingBuffer
	self.cursor = 0
	return self
end

--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

-- Makes sure there is room for `bytes` more bytes at the cursor, growing the buffer if needed.
function BufferSerializer:_ensure(bytes: number)
	local needed = self.cursor + bytes
	local size = buffer.len(self.buffer)
	if needed <= size then
		return
	end

	local newSize = math.max(size * 2, needed)
	local newBuffer = buffer.create(newSize)
	buffer.copy(newBuffer, 0, self.buffer, 0, size)
	self.buffer = newBuffer
end

--------------------------------------------------------------------------------
-- Cursor & buffer utilities
--------------------------------------------------------------------------------

function BufferSerializer:Reset()
	self.cursor = 0
end

function BufferSerializer:GetCursor(): number
	return self.cursor
end

function BufferSerializer:SetCursor(position: number)
	assert(position >= 0 and position <= buffer.len(self.buffer), "Cursor position out of range")
	self.cursor = position
end

function BufferSerializer:Skip(bytes: number)
	self:SetCursor(self.cursor + bytes)
end

-- Total size of the underlying buffer (including unused space).
function BufferSerializer:GetSize(): number
	return buffer.len(self.buffer)
end

-- Bytes left between the cursor and the end of the buffer.
function BufferSerializer:Remaining(): number
	return buffer.len(self.buffer) - self.cursor
end

-- Returns the underlying buffer as-is, including any unused space at the end.
function BufferSerializer:GetBuffer(): buffer
	return self.buffer
end

-- Returns a new buffer containing only the bytes up to the cursor. Use this before sending over the network.
function BufferSerializer:ToBuffer(): buffer
	local out = buffer.create(self.cursor)
	buffer.copy(out, 0, self.buffer, 0, self.cursor)
	return out
end

-- Runs a read function without moving the cursor.
-- Example: local nextType = serializer:Peek(serializer.ReadUInt8)
function BufferSerializer:Peek<T>(readFn: (BufferSerializer) -> T): T
	local saved = self.cursor
	local value = readFn(self)
	self.cursor = saved
	return value
end

--------------------------------------------------------------------------------
-- Unsigned integers
--------------------------------------------------------------------------------

function BufferSerializer:WriteUInt8(value: number)
	self:_ensure(1)
	buffer.writeu8(self.buffer, self.cursor, value)
	self.cursor += 1
end

function BufferSerializer:ReadUInt8(): number
	local value = buffer.readu8(self.buffer, self.cursor)
	self.cursor += 1
	return value
end

function BufferSerializer:WriteUInt16(value: number)
	self:_ensure(2)
	buffer.writeu16(self.buffer, self.cursor, value)
	self.cursor += 2
end

function BufferSerializer:ReadUInt16(): number
	local value = buffer.readu16(self.buffer, self.cursor)
	self.cursor += 2
	return value
end

function BufferSerializer:WriteUInt32(value: number)
	self:_ensure(4)
	buffer.writeu32(self.buffer, self.cursor, value)
	self.cursor += 4
end

function BufferSerializer:ReadUInt32(): number
	local value = buffer.readu32(self.buffer, self.cursor)
	self.cursor += 4
	return value
end

--------------------------------------------------------------------------------
-- Signed integers
--------------------------------------------------------------------------------

function BufferSerializer:WriteInt8(value: number)
	self:_ensure(1)
	buffer.writei8(self.buffer, self.cursor, value)
	self.cursor += 1
end

function BufferSerializer:ReadInt8(): number
	local value = buffer.readi8(self.buffer, self.cursor)
	self.cursor += 1
	return value
end

function BufferSerializer:WriteInt16(value: number)
	self:_ensure(2)
	buffer.writei16(self.buffer, self.cursor, value)
	self.cursor += 2
end

function BufferSerializer:ReadInt16(): number
	local value = buffer.readi16(self.buffer, self.cursor)
	self.cursor += 2
	return value
end

function BufferSerializer:WriteInt32(value: number)
	self:_ensure(4)
	buffer.writei32(self.buffer, self.cursor, value)
	self.cursor += 4
end

function BufferSerializer:ReadInt32(): number
	local value = buffer.readi32(self.buffer, self.cursor)
	self.cursor += 4
	return value
end

--------------------------------------------------------------------------------
-- Variable-length unsigned integer (LEB128)
-- 0-127 = 1 byte, up to 16383 = 2 bytes, ... up to 2^32 - 1 = 5 bytes.
-- Great for lengths and counts that are usually small.
--------------------------------------------------------------------------------

function BufferSerializer:WriteVarUInt(value: number)
	assert(value >= 0 and value <= 0xFFFFFFFF and value % 1 == 0, "VarUInt must be a whole number from 0 to 4294967295")
	repeat
		local byte = value % 128
		value = (value - byte) // 128
		if value > 0 then
			byte += 128 -- continuation bit
		end
		self:WriteUInt8(byte)
	until value == 0
end

function BufferSerializer:ReadVarUInt(): number
	local result = 0
	local multiplier = 1
	repeat
		local byte = self:ReadUInt8()
		result += (byte % 128) * multiplier
		multiplier *= 128
	until byte < 128
	return result
end

--------------------------------------------------------------------------------
-- Floats
--------------------------------------------------------------------------------

function BufferSerializer:WriteFloat32(value: number)
	self:_ensure(4)
	buffer.writef32(self.buffer, self.cursor, value)
	self.cursor += 4
end

function BufferSerializer:ReadFloat32(): number
	local value = buffer.readf32(self.buffer, self.cursor)
	self.cursor += 4
	return value
end

function BufferSerializer:WriteFloat64(value: number)
	self:_ensure(8)
	buffer.writef64(self.buffer, self.cursor, value)
	self.cursor += 8
end

function BufferSerializer:ReadFloat64(): number
	local value = buffer.readf64(self.buffer, self.cursor)
	self.cursor += 8
	return value
end

-- Stores a number within [min, max] in 2 bytes (65536 steps). Values outside the range are clamped.
-- Precision is (max - min) / 65535, e.g. 0-100 gives roughly 0.0015 precision.
function BufferSerializer:WriteQuantizedFloat(value: number, min: number, max: number)
	assert(max > min, "max must be greater than min")
	local alpha = (math.clamp(value, min, max) - min) / (max - min)
	self:WriteUInt16(math.round(alpha * 65535))
end

function BufferSerializer:ReadQuantizedFloat(min: number, max: number): number
	return min + (self:ReadUInt16() / 65535) * (max - min)
end

--------------------------------------------------------------------------------
-- Booleans
--------------------------------------------------------------------------------

function BufferSerializer:WriteBool(value: boolean)
	self:WriteUInt8(if value then 1 else 0)
end

function BufferSerializer:ReadBool(): boolean
	return self:ReadUInt8() ~= 0
end

-- Packs up to 8 booleans into a single byte.
function BufferSerializer:WriteBools(...: boolean)
	local count = select("#", ...)
	assert(count >= 1 and count <= 8, "WriteBools takes between 1 and 8 booleans")
	local byte = 0
	for i = 1, count do
		if (select(i, ...)) then
			byte = bit32.bor(byte, bit32.lshift(1, i - 1))
		end
	end
	self:WriteUInt8(byte)
end

-- Reads `count` booleans packed by WriteBools. Returns them as separate values.
function BufferSerializer:ReadBools(count: number): ...boolean
	assert(count >= 1 and count <= 8, "ReadBools takes a count between 1 and 8")
	local byte = self:ReadUInt8()
	local results = table.create(count)
	for i = 1, count do
		results[i] = bit32.btest(byte, bit32.lshift(1, i - 1))
	end
	return table.unpack(results, 1, count)
end

--------------------------------------------------------------------------------
-- Strings & raw buffers
--------------------------------------------------------------------------------

function BufferSerializer:WriteString(str: string)
	local len = #str
	self:WriteVarUInt(len)
	self:_ensure(len)
	buffer.writestring(self.buffer, self.cursor, str, len)
	self.cursor += len
end

function BufferSerializer:ReadString(): string
	local len = self:ReadVarUInt()
	local str = buffer.readstring(self.buffer, self.cursor, len)
	self.cursor += len
	return str
end

function BufferSerializer:WriteBuffer(source: buffer)
	local len = buffer.len(source)
	self:WriteVarUInt(len)
	self:_ensure(len)
	buffer.copy(self.buffer, self.cursor, source, 0, len)
	self.cursor += len
end

function BufferSerializer:ReadBuffer(): buffer
	local len = self:ReadVarUInt()
	local out = buffer.create(len)
	buffer.copy(out, 0, self.buffer, self.cursor, len)
	self.cursor += len
	return out
end

--------------------------------------------------------------------------------
-- Vectors
--------------------------------------------------------------------------------

function BufferSerializer:WriteVector2(vector: Vector2)
	self:WriteFloat32(vector.X)
	self:WriteFloat32(vector.Y)
end

function BufferSerializer:ReadVector2(): Vector2
	local x = self:ReadFloat32()
	local y = self:ReadFloat32()
	return Vector2.new(x, y)
end

function BufferSerializer:WriteVector3(vector: Vector3)
	self:WriteFloat32(vector.X)
	self:WriteFloat32(vector.Y)
	self:WriteFloat32(vector.Z)
end

function BufferSerializer:ReadVector3(): Vector3
	local x = self:ReadFloat32()
	local y = self:ReadFloat32()
	local z = self:ReadFloat32()
	return Vector3.new(x, y, z)
end

-- 6 bytes. Each axis must be a whole number from -32768 to 32767. Good for grid positions.
function BufferSerializer:WriteVector3int16(vector: Vector3int16)
	self:WriteInt16(vector.X)
	self:WriteInt16(vector.Y)
	self:WriteInt16(vector.Z)
end

function BufferSerializer:ReadVector3int16(): Vector3int16
	local x = self:ReadInt16()
	local y = self:ReadInt16()
	local z = self:ReadInt16()
	return Vector3int16.new(x, y, z)
end

--------------------------------------------------------------------------------
-- CFrames
--------------------------------------------------------------------------------

-- Full precision CFrame: 48 bytes (12 for position, 36 for the rotation matrix).
function BufferSerializer:WriteCFrame(cf: CFrame)
	local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cf:GetComponents()

	-- Position (12 bytes)
	self:WriteFloat32(x)
	self:WriteFloat32(y)
	self:WriteFloat32(z)

	-- Rotation matrix (36 bytes)
	self:WriteFloat32(R00)
	self:WriteFloat32(R01)
	self:WriteFloat32(R02)
	self:WriteFloat32(R10)
	self:WriteFloat32(R11)
	self:WriteFloat32(R12)
	self:WriteFloat32(R20)
	self:WriteFloat32(R21)
	self:WriteFloat32(R22)
end

function BufferSerializer:ReadCFrame(): CFrame
	local x = self:ReadFloat32()
	local y = self:ReadFloat32()
	local z = self:ReadFloat32()

	local R00 = self:ReadFloat32()
	local R01 = self:ReadFloat32()
	local R02 = self:ReadFloat32()
	local R10 = self:ReadFloat32()
	local R11 = self:ReadFloat32()
	local R12 = self:ReadFloat32()
	local R20 = self:ReadFloat32()
	local R21 = self:ReadFloat32()
	local R22 = self:ReadFloat32()

	return CFrame.new(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22)
end

-- Compact CFrame: 28 bytes (12 for position, 16 for a rotation quaternion).
function BufferSerializer:WriteCFrameCompact(cf: CFrame)
	local x, y, z, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cf:GetComponents()

	local qx, qy, qz, qw
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		qw = 0.25 * s
		qx = (m21 - m12) / s
		qy = (m02 - m20) / s
		qz = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		qw = (m21 - m12) / s
		qx = 0.25 * s
		qy = (m01 + m10) / s
		qz = (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		qw = (m02 - m20) / s
		qx = (m01 + m10) / s
		qy = 0.25 * s
		qz = (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		qw = (m10 - m01) / s
		qx = (m02 + m20) / s
		qy = (m12 + m21) / s
		qz = 0.25 * s
	end

	self:WriteFloat32(x)
	self:WriteFloat32(y)
	self:WriteFloat32(z)
	self:WriteFloat32(qx)
	self:WriteFloat32(qy)
	self:WriteFloat32(qz)
	self:WriteFloat32(qw)
end

function BufferSerializer:ReadCFrameCompact(): CFrame
	local x = self:ReadFloat32()
	local y = self:ReadFloat32()
	local z = self:ReadFloat32()
	local qx = self:ReadFloat32()
	local qy = self:ReadFloat32()
	local qz = self:ReadFloat32()
	local qw = self:ReadFloat32()
	return CFrame.new(x, y, z, qx, qy, qz, qw)
end

--------------------------------------------------------------------------------
-- Colours & UI
--------------------------------------------------------------------------------

-- 3 bytes (0-255 per channel). Colours outside 0-1 are clamped.
function BufferSerializer:WriteColor3(colour: Color3)
	self:WriteUInt8(math.clamp(math.round(colour.R * 255), 0, 255))
	self:WriteUInt8(math.clamp(math.round(colour.G * 255), 0, 255))
	self:WriteUInt8(math.clamp(math.round(colour.B * 255), 0, 255))
end

function BufferSerializer:ReadColor3(): Color3
	local r = self:ReadUInt8()
	local g = self:ReadUInt8()
	local b = self:ReadUInt8()
	return Color3.fromRGB(r, g, b)
end

-- 8 bytes: Float32 scale, Int32 offset.
function BufferSerializer:WriteUDim(udim: UDim)
	self:WriteFloat32(udim.Scale)
	self:WriteInt32(udim.Offset)
end

function BufferSerializer:ReadUDim(): UDim
	local scale = self:ReadFloat32()
	local offset = self:ReadInt32()
	return UDim.new(scale, offset)
end

function BufferSerializer:WriteUDim2(udim2: UDim2)
	self:WriteUDim(udim2.X)
	self:WriteUDim(udim2.Y)
end

function BufferSerializer:ReadUDim2(): UDim2
	local x = self:ReadUDim()
	local y = self:ReadUDim()
	return UDim2.new(x, y)
end

--------------------------------------------------------------------------------
-- Enums
--------------------------------------------------------------------------------

-- Writes an EnumItem by its Value. You need to know which Enum it belongs to when reading.
function BufferSerializer:WriteEnum(item: EnumItem)
	self:WriteVarUInt(item.Value)
end

-- Example: serializer:ReadEnum(Enum.Material)
function BufferSerializer:ReadEnum(enumType: Enum): EnumItem
	local value = self:ReadVarUInt()
	local item = enumType:FromValue(value)
	assert(item, `No {enumType} item with value {value}`)
	return item
end

--------------------------------------------------------------------------------
-- Arrays
--------------------------------------------------------------------------------

-- Writes the array length followed by each element using writeFn.
-- Example: serializer:WriteArray(positions, serializer.WriteVector3)
function BufferSerializer:WriteArray<T>(list: { T }, writeFn: (BufferSerializer, T) -> ())
	self:WriteVarUInt(#list)
	for _, value in list do
		writeFn(self, value)
	end
end

-- Example: local positions = serializer:ReadArray(serializer.ReadVector3)
function BufferSerializer:ReadArray<T>(readFn: (BufferSerializer) -> T): { T }
	local count = self:ReadVarUInt()
	local out = table.create(count)
	for i = 1, count do
		out[i] = readFn(self)
	end
	return out
end

return BufferSerializer

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Numerics;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace TerraformGraph
{
    // System.Text.Json-backed replacement for ConvertTo-Json / ConvertFrom-Json.
    // The built-in cmdlets cap depth at 100 and truncate (or fail) on deep documents
    // such as `terraform providers schema -json` for the AWS provider.
    public static class Json
    {
        public static string Serialize(object value, int maxDepth, bool compress)
        {
            var options = new JsonWriterOptions
            {
                Indented = !compress,
                MaxDepth = maxDepth,
                // Keep <, >, &, ' and non-ASCII readable instead of < style escapes.
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            };

            using var stream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(stream, options))
            {
                new Writer(writer, maxDepth).Write(value, 0);
            }
            return Encoding.UTF8.GetString(stream.ToArray());
        }

        public static object Deserialize(string json, int maxDepth, bool asHashtable)
        {
            var options = new JsonDocumentOptions
            {
                MaxDepth = maxDepth,
                CommentHandling = JsonCommentHandling.Skip,
                AllowTrailingCommas = true,
            };

            using var document = JsonDocument.Parse(json, options);
            return Read(document.RootElement, asHashtable);
        }

        private static object Read(JsonElement element, bool asHashtable)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.Object:
                    if (asHashtable)
                    {
                        var table = new OrderedDictionary(StringComparer.Ordinal);
                        foreach (var property in element.EnumerateObject())
                        {
                            table[property.Name] = Read(property.Value, true);
                        }
                        return table;
                    }

                    var obj = new PSObject();
                    foreach (var property in element.EnumerateObject())
                    {
                        if (property.Name.Length == 0 || obj.Properties[property.Name] != null)
                        {
                            throw new InvalidDataException(
                                $"Key '{property.Name}' is empty or collides with another key (PSCustomObject keys are case-insensitive). Use -AsHashtable.");
                        }
                        obj.Properties.Add(new PSNoteProperty(property.Name, Read(property.Value, false)));
                    }
                    return obj;

                case JsonValueKind.Array:
                    var items = new List<object>(element.GetArrayLength());
                    foreach (var item in element.EnumerateArray())
                    {
                        items.Add(Read(item, asHashtable));
                    }
                    return items.ToArray();

                case JsonValueKind.String:
                    return element.GetString();

                case JsonValueKind.Number:
                    if (element.TryGetInt32(out int i)) return i;
                    if (element.TryGetInt64(out long l)) return l;
                    string raw = element.GetRawText();
                    if (raw.IndexOfAny(new[] { '.', 'e', 'E' }) < 0)
                    {
                        return BigInteger.Parse(raw, CultureInfo.InvariantCulture);
                    }
                    return element.GetDouble();

                case JsonValueKind.True:
                    return true;

                case JsonValueKind.False:
                    return false;

                default:
                    return null;
            }
        }

        private sealed class Writer
        {
            private readonly Utf8JsonWriter _writer;
            private readonly int _maxDepth;
            private readonly HashSet<object> _path = new HashSet<object>(ReferenceEqualityComparer.Instance);

            public Writer(Utf8JsonWriter writer, int maxDepth)
            {
                _writer = writer;
                _maxDepth = maxDepth;
            }

            public void Write(object value, int depth)
            {
                if (value is PSObject pso)
                {
                    if (pso == System.Management.Automation.Internal.AutomationNull.Value)
                    {
                        _writer.WriteNullValue();
                        return;
                    }
                    if (pso.BaseObject is PSCustomObject)
                    {
                        // Every [pscustomobject] shares one BaseObject, so the wrapper is the identity.
                        WriteProperties(pso, pso, depth);
                        return;
                    }
                    value = pso.BaseObject;
                }

                switch (value)
                {
                    case null:
                    case DBNull _:
                        _writer.WriteNullValue();
                        return;
                    case string s:
                        _writer.WriteStringValue(s);
                        return;
                    case char c:
                        _writer.WriteStringValue(c.ToString());
                        return;
                    case bool b:
                        _writer.WriteBooleanValue(b);
                        return;
                    case byte or sbyte or short or ushort or int or long:
                        _writer.WriteNumberValue(Convert.ToInt64(value, CultureInfo.InvariantCulture));
                        return;
                    case uint or ulong:
                        _writer.WriteNumberValue(Convert.ToUInt64(value, CultureInfo.InvariantCulture));
                        return;
                    case float f:
                        WriteFloatingPoint(f);
                        return;
                    case double d:
                        WriteFloatingPoint(d);
                        return;
                    case decimal m:
                        _writer.WriteNumberValue(m);
                        return;
                    case BigInteger bi:
                        _writer.WriteRawValue(bi.ToString(CultureInfo.InvariantCulture));
                        return;
                    case DateTime dt:
                        _writer.WriteStringValue(dt.ToString("o", CultureInfo.InvariantCulture));
                        return;
                    case DateTimeOffset dto:
                        _writer.WriteStringValue(dto.ToString("o", CultureInfo.InvariantCulture));
                        return;
                    case Enum or Guid or Uri or Version or TimeSpan or ScriptBlock:
                        _writer.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture));
                        return;
                    case Type t:
                        _writer.WriteStringValue(t.FullName);
                        return;
                    case IDictionary dictionary:
                        WriteDictionary(dictionary, depth);
                        return;
                    case IEnumerable enumerable:
                        WriteArray(enumerable, depth);
                        return;
                    default:
                        WriteProperties(PSObject.AsPSObject(value), value, depth);
                        return;
                }
            }

            private void WriteFloatingPoint(double d)
            {
                if (double.IsFinite(d))
                {
                    _writer.WriteNumberValue(d);
                }
                else
                {
                    _writer.WriteStringValue(d.ToString(CultureInfo.InvariantCulture));
                }
            }

            private void WriteDictionary(IDictionary dictionary, int depth)
            {
                Enter(dictionary, depth);
                _writer.WriteStartObject();
                foreach (DictionaryEntry entry in dictionary)
                {
                    _writer.WritePropertyName(Convert.ToString(entry.Key, CultureInfo.InvariantCulture));
                    Write(entry.Value, depth + 1);
                }
                _writer.WriteEndObject();
                _path.Remove(dictionary);
            }

            private void WriteArray(IEnumerable enumerable, int depth)
            {
                Enter(enumerable, depth);
                _writer.WriteStartArray();
                foreach (var item in enumerable)
                {
                    Write(item, depth + 1);
                }
                _writer.WriteEndArray();
                _path.Remove(enumerable);
            }

            private void WriteProperties(PSObject pso, object identity, int depth)
            {
                Enter(identity, depth);
                _writer.WriteStartObject();
                foreach (var property in pso.Properties)
                {
                    if (!property.IsGettable)
                    {
                        continue;
                    }
                    object propertyValue;
                    try
                    {
                        propertyValue = property.Value;
                    }
                    catch (GetValueException)
                    {
                        propertyValue = null;
                    }
                    _writer.WritePropertyName(property.Name);
                    Write(propertyValue, depth + 1);
                }
                _writer.WriteEndObject();
                _path.Remove(identity);
            }

            private void Enter(object identity, int depth)
            {
                if (depth >= _maxDepth)
                {
                    throw new InvalidDataException($"Object nesting exceeds -Depth {_maxDepth}.");
                }
                if (!_path.Add(identity))
                {
                    throw new InvalidDataException(
                        $"Circular reference detected at depth {depth} ({identity.GetType().FullName}).");
                }
            }
        }
    }
}

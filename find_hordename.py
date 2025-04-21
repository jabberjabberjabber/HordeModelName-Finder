import sys
import struct
import json
import re
import os
from enum import IntEnum
from difflib import SequenceMatcher

class GGUFValueType(IntEnum):
    STRING = 8

class GGUFMetadataReader:
    def __init__(self, filename):
        self.file = open(filename, 'rb')
        self.metadata = self._read_metadata()
        self.file.close()
    
    def _read_header(self):
        self.file.read(4)  # Skip magic
        self.file.read(4)  # Skip version
        self.file.read(8)  # Skip tensor_count
        metadata_kv_count = struct.unpack('<Q', self.file.read(8))[0]
        return metadata_kv_count
    
    def _read_string(self):
        length = struct.unpack('<Q', self.file.read(8))[0]
        return self.file.read(length).decode('utf-8')
    
    def _read_value(self, value_type):
        if value_type == GGUFValueType.STRING:
            return self._read_string()
        else:
            return None
    
    def _read_metadata(self):
        metadata = {}
        metadata_kv_count = self._read_header()
        
        for _ in range(metadata_kv_count):
            try:
                key = self._read_string()
            except:
                continue
                
            value_type = struct.unpack('<I', self.file.read(4))[0]
            if value_type == GGUFValueType.STRING.value:
                value = self._read_value(GGUFValueType.STRING)
                metadata[key] = value
                if key == "general.name":
                    break
            else:
                # Skip other value types
                continue
        return metadata

class ModelNameMapper:
    def __init__(self, horde_models_path):
        with open(horde_models_path, 'r', encoding='utf-8') as f:
            self.horde_models = json.load(f)
    
    def _normalize(self, text):
        if not text:
            return ""
        text = str(text).lower()
        text = re.sub(r'[^a-z0-9]', '', text)
        return text
    
    def _get_similarity(self, str1, str2):
        if not str1 or not str2:
            return 0
        return SequenceMatcher(None, str1, str2).ratio()
    
    def get_model_name(self, gguf_path):
        try:
            reader = GGUFMetadataReader(gguf_path)
            metadata = reader.metadata
            
            identifiers = []
            if "general.name" in metadata:
                identifiers.append(metadata["general.name"])
            
            if len(identifiers) == 0:
                basename = os.path.basename(gguf_path)
                basename = re.sub(r'\.gguf$', '', basename)
                basename = re.sub(r'[-_]?Q\d+(?:_[A-Z_]+)?$', '', basename)
                identifiers.append(basename)

            normalized_identifiers = [self._normalize(id) for id in identifiers if id]
            
            best_match = None
            best_score = 0
            
            for model_id, model_data in self.horde_models.items():
                model_short_name = model_data.get("model_name", "")
                
                for norm_id in normalized_identifiers:
                    norm_name = self._normalize(model_short_name)
                    if not norm_name:
                        continue
                        
                    similarity = self._get_similarity(norm_id, norm_name)
                    
                    if norm_id in norm_name or norm_name in norm_id:
                        similarity = max(similarity, 0.7)
                    
                    if similarity > best_score:
                        best_score = similarity
                        best_match = model_short_name
            
            if best_score >= 0.5:
                return best_match
            return ""
            
        except Exception as e:
            return ""

def main():
    gguf_path = sys.argv[1]
    horde_models_path = sys.argv[2]
    
    mapper = ModelNameMapper(horde_models_path)
    model_name = mapper.get_model_name(gguf_path)
    
    print(model_name)

if __name__ == "__main__":
    main()
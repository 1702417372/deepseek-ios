
from openstep_parser import OpenStepDecoder
from pbxproj import XcodeProject
path = r"D:\39945\文档\deepseek-harness\default-workspace\deepseek-clone\\DeepSeekClone.xcodeproj\\project.pbxproj"
with open(path, encoding="utf-8") as f:
    text = f.read()
obj = OpenStepDecoder.ParseFromString(text)
print("openstep parse OK, top keys:", list(obj.keys())[:5])
proj = XcodeProject.load(path)
t = proj.objects.get_targets()[0]
print("target:", t.name)
print("sources:", len(proj.objects.get_objects_in_section("PBXSourcesBuildPhase")[0].files))
print("resources:", len(proj.objects.get_objects_in_section("PBXResourcesBuildPhase")[0].files))
print("OK")

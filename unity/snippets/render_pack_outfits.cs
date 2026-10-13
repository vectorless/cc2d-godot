// Body of an MCP-for-Unity execute_code call (not a compiled script). For each new pack and body
// type it dresses a copy of Exa in that pack's parts, saves the CharacterData to
// characters/packs/<id>.json and renders Unity's reference image (Idle, frame 0, the default
// export camera, gray background) to tests/shots/packs/<id>_unity.png for tests/packs_test.
// Materials are instantiated first so the project's material assets are NOT modified.
var outDir = "/Users/pa/Games/cc2d-godot/";
var prefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/CharacterCreator2D/Examples/Exa.prefab");
var packs = new[]{"Daily", "Post Apocalyptic", "Undead"};
var bodies = new[]{CharacterCreator2D.BodyType.Male, CharacterCreator2D.BodyType.Female};
var cats = (CharacterCreator2D.SlotCategory[])System.Enum.GetValues(typeof(CharacterCreator2D.SlotCategory));
var camGo = new GameObject("TmpCam"); var cam = camGo.AddComponent<Camera>();
cam.orthographic = true; cam.orthographicSize = 10f; cam.transform.position = new Vector3(1000, 6, -10);
cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.5f,0.5f,0.5f,1);
var rt = new RenderTexture(512, 512, 24); cam.targetTexture = rt;
AnimationClip idle = null;
foreach (var c in AnimationUtility.GetAnimationClips(prefab)) if (c.name == "Idle") idle = c;
var made = new System.Collections.Generic.List<Material>();
foreach (var pack in packs) foreach (var body in bodies) for (int outfit = 0; outfit < 2; outfit++) {
  var go = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
  PrefabUtility.UnpackPrefabInstance(go, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
  go.transform.position = new Vector3(1000, 0, 0);
  var cv = go.GetComponent<CharacterCreator2D.CharacterViewer>();
  typeof(CharacterCreator2D.CharacterViewer).GetMethod("instantiateSlotsMaterial", System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance).Invoke(cv, null);
  foreach (var cat in cats) { var m = cv.slots.GetSlot(cat).material; if (m != null && !AssetDatabase.Contains(m) && !made.Contains(m)) made.Add(m); }
  cv.RelinkMaterials();
  cv.SetBodyType(body);
  foreach (var cat in cats) {
    var cands = new System.Collections.Generic.List<CharacterCreator2D.Part>();
    foreach (var pk in CharacterCreator2D.PartList.Static.partPacks) foreach (var p in pk.parts) {
      if (p == null || p.packageName != pack || !p.supportedBody.Contains(body)) continue;
      bool ok = false;
      if (cat == CharacterCreator2D.SlotCategory.MainHand || cat == CharacterCreator2D.SlotCategory.OffHand) {
        var w = p as CharacterCreator2D.Weapon;
        if (w != null && pk.category == CharacterCreator2D.PartCategory.Weapon) {
          if (cat == CharacterCreator2D.SlotCategory.MainHand) ok = w.weaponCategory == CharacterCreator2D.WeaponCategory.OneHanded || w.weaponCategory == CharacterCreator2D.WeaponCategory.TwoHanded;
          else ok = outfit == 1 && w.weaponCategory == CharacterCreator2D.WeaponCategory.OneHanded;
        }
      } else ok = pk.category.ToString() == cat.ToString();
      if (ok) cands.Add(p);
    }
    if (cands.Count == 0) continue;
    var part = cands[(outfit * 3 + (int)body) % cands.Count];
    if (cat == CharacterCreator2D.SlotCategory.OffHand && outfit == 1) part = cands[cands.Count - 1];
    cv.EquipPart(cat, part);
  }
  if (idle != null) idle.SampleAnimation(go, 0f);
  var id = (pack.Replace(" ", "_") + "_" + body + "_" + outfit).ToLower();
  cv.SaveToJSON(outDir + "characters/packs/" + id + ".json");
  cam.Render();
  RenderTexture.active = rt; var img = new Texture2D(512, 512, TextureFormat.RGB24, false); img.ReadPixels(new Rect(0,0,512,512),0,0); img.Apply(); RenderTexture.active = null;
  System.IO.Directory.CreateDirectory(outDir + "tests/shots/packs");
  System.IO.File.WriteAllBytes(outDir + "tests/shots/packs/" + id + "_unity.png", img.EncodeToPNG());
  UnityEngine.Object.DestroyImmediate(img);
  UnityEngine.Object.DestroyImmediate(go);
}
foreach (var m in made) UnityEngine.Object.DestroyImmediate(m);
UnityEngine.Object.DestroyImmediate(camGo); rt.Release();
return "done";

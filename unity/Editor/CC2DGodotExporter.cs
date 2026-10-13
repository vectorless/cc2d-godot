// Character Creator 2D -> Godot 4 exporter (v2).
//
// Writes, into the Godot project:
//   cc2d/rigs/<body>.json         body-type skeletons (from SetupData body prefabs) + baked cape/skirt meshes
//   cc2d/animations/<ctrl>.json   animator states as per-component value tracks (only what each clip animates)
//   cc2d/parts.json               the full part catalogue + SetupData link tables
//   cc2d/textures/...             every texture referenced above
//   characters/<id>/character.json  a CharacterViewer's body type, slots, materials and colours
//
// Coordinates: Godot px = Unity units * 100, Y flipped, rotations negated (a mirror about X,
// applied consistently to every local transform, so hierarchies stay correct).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using CharacterCreator2D;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

public static class CC2DGodotExporter
{
    public const string DefaultGodotProject = "/Users/pa/Games/cc2d-godot";
    const float UnitToPx = 100f;
    const float SampleFps = 30f;
    const string SpritesRoot = "Assets/CharacterCreator2D/Sprites/";
    const string DefaultController = "Assets/CharacterCreator2D/Data/Animations/CC2D.controller";
    static readonly CultureInfo CI = CultureInfo.InvariantCulture;

    class Ctx
    {
        public string project;
        public readonly StringBuilder log = new StringBuilder();
        public readonly Dictionary<Texture2D, string> textures = new Dictionary<Texture2D, string>();
        public readonly HashSet<string> warned = new HashSet<string>();
        public int copied;
        public void Warn(string msg) { if (warned.Add(msg)) log.AppendLine(msg); }
    }

    // ---------------------------------------------------------------- menu
    [MenuItem("Tools/CC2D/Export Selected Character to Godot")]
    static void ExportSelectedMenu()
    {
        var go = Selection.activeGameObject;
        if (go == null || go.GetComponent<CharacterViewer>() == null)
        {
            EditorUtility.DisplayDialog("CC2D → Godot", "Select a Character Creator 2D character (prefab or scene object) first.", "OK");
            return;
        }
        Debug.Log(Export(go, DefaultGodotProject, Sanitize(go.name)));
    }

    [MenuItem("Tools/CC2D/Export Shared Data (rigs, animations, parts) to Godot")]
    static void ExportSharedMenu()
    {
        var ctx = new Ctx { project = DefaultGodotProject };
        ExportShared(ctx, null);
        Debug.Log(ctx.log.ToString());
    }

    public static string Sanitize(string s)
    {
        var sb = new StringBuilder();
        foreach (var c in s.ToLowerInvariant()) sb.Append(char.IsLetterOrDigit(c) ? c : '_');
        return sb.ToString();
    }

    // ---------------------------------------------------------------- character
    public static string Export(GameObject character, string godotProject, string id)
    {
        var ctx = new Ctx { project = godotProject };
        var viewer = character.GetComponent<CharacterViewer>();
        if (viewer == null) throw new ArgumentException(character.name + " has no CharacterViewer");
        var animator = character.GetComponent<Animator>();
        string animRes = ExportShared(ctx, animator ? animator.runtimeAnimatorController : null);

        var materials = new Dictionary<Material, string>();
        var slots = new StringBuilder("{");
        bool first = true;
        foreach (SlotCategory cat in Enum.GetValues(typeof(SlotCategory)))
        {
            var slot = viewer.slots.GetSlot(cat);
            if (!first) slots.Append(",");
            first = false;
            string partName = slot.assignedPart ? slot.assignedPart.name : slot.AssignedPartName;
            string package = slot.assignedPart ? slot.assignedPart.packageName : slot.AssignedPackageName;
            slots.Append("\n").Append(Q(cat.ToString())).Append(":{");
            slots.Append("\"material\":").Append(slot.material ? Q(MaterialKey(slot.material, materials)) : "null");
            slots.Append(",\"part\":").Append(string.IsNullOrEmpty(partName) ? "null" : Q(partName));
            slots.Append(",\"package\":").Append(Q(package ?? ""));
            slots.Append(",\"color1\":").Append(Col(slot.color1));
            slots.Append(",\"color2\":").Append(Col(slot.color2));
            slots.Append(",\"color3\":").Append(Col(slot.color3));
            slots.Append("}");
        }
        slots.Append("\n}");

        var sb = new StringBuilder();
        sb.Append("{\"format\":2,\"id\":").Append(Q(id)).Append(",\"source\":").Append(Q(character.name));
        sb.Append(",\"body_type\":").Append(Q(viewer.bodyType.ToString()));
        sb.Append(",\"skin_color\":").Append(Col(viewer.SkinColor));
        sb.Append(",\"tint_color\":").Append(Col(viewer.TintColor));
        sb.Append(",\"parts\":\"res://cc2d/parts.json\"");
        sb.Append(",\"rigs\":{");
        bool fr = true;
        foreach (BodyType bt in Enum.GetValues(typeof(BodyType)))
        {
            if (!fr) sb.Append(",");
            fr = false;
            sb.Append(Q(bt.ToString())).Append(":").Append(Q(RigRes(bt)));
        }
        sb.Append("}");
        sb.Append(",\"animations\":").Append(Q(animRes));
        sb.Append(",\"default_animation\":\"Idle\"");
        sb.Append(",\"materials\":").Append(MaterialsJson(materials, ctx));
        sb.Append(",\"slots\":").Append(slots);
        sb.Append(",\"emotes\":").Append(EmotesJson(viewer));
        sb.Append("}\n");

        var outDir = Path.Combine(godotProject, "characters", id);
        Directory.CreateDirectory(outDir);
        File.WriteAllText(Path.Combine(outDir, "character.json"), sb.ToString());
        ctx.log.Insert(0, string.Format(CI, "Exported character '{0}' ({1}) -> {2}; textures {3} ({4} copied)\n",
            character.name, viewer.bodyType, outDir, ctx.textures.Count, ctx.copied));
        return ctx.log.ToString();
    }

    // CharacterViewer.emotes: which face parts each emotion swaps in (null = keep default face part).
    static readonly SlotCategory[] FaceSlots = { SlotCategory.Eyebrow, SlotCategory.Eyes, SlotCategory.Nose, SlotCategory.Mouth, SlotCategory.Ear };

    static string EmotesJson(CharacterViewer viewer)
    {
        var sb = new StringBuilder("{");
        bool first = true;
        foreach (EmotionType et in Enum.GetValues(typeof(EmotionType)))
        {
            var e = viewer.emotes.getIndex(et);
            if (!first) sb.Append(",");
            first = false;
            sb.Append("\n").Append(Q(et.ToString())).Append(":{\"index\":").Append((int)et);
            sb.Append(",\"name\":").Append(Q(e != null && !string.IsNullOrEmpty(e.name) ? e.name : et.ToString()));
            foreach (var slot in FaceSlots)
            {
                var part = e != null ? e.getPart(slot) : null;
                sb.Append(",").Append(Q(slot.ToString())).Append(":");
                if (part == null) sb.Append("null");
                else sb.Append("{\"name\":").Append(Q(part.name)).Append(",\"package\":").Append(Q(part.packageName ?? "")).Append("}");
            }
            sb.Append("}");
        }
        return sb.Append("\n}").ToString();
    }

    static string ExportShared(Ctx ctx, RuntimeAnimatorController rac)
    {
        if (rac == null) rac = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(DefaultController);
        var clips = ClipsOf(rac);
        foreach (BodyType bt in Enum.GetValues(typeof(BodyType))) ExportRig(ctx, bt, clips);
        string animRes = "res://cc2d/animations/" + Sanitize(rac.name) + ".json";
        _lastController = rac;
        ExportAnimations(ctx, clips, animRes);
        ExportPartCatalogue(ctx);
        return animRes;
    }

    static string RigRes(BodyType bt) { return "res://cc2d/rigs/" + bt.ToString().ToLowerInvariant() + ".json"; }

    static string ResToPath(Ctx ctx, string res) { return Path.Combine(ctx.project, res.Substring("res://".Length)); }

    static void WriteRes(Ctx ctx, string res, string content)
    {
        var path = ResToPath(ctx, res);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, content);
    }

    // ---------------------------------------------------------------- rigs
    static void ExportRig(Ctx ctx, BodyType bt, List<KeyValuePair<string, AnimationClip>> clips)
    {
        var sd = SetupData.Static;
        var body = sd.GetBodyPrefab(bt);
        if (body == null) { ctx.Warn("No body prefab for " + bt); return; }
        var materials = new Dictionary<Material, string>();

        var nodes = new StringBuilder("[");
        bool first = true;
        int nodeCount = 0;
        foreach (var t in body.GetComponentsInChildren<Transform>(true))
        {
            if (!first) nodes.Append(",");
            first = false;
            nodeCount++;
            nodes.Append("\n{\"path\":").Append(Q(RigPath(t, body)));
            nodes.Append(",\"name\":").Append(Q(t == body ? "Root" : t.name));
            nodes.Append(",\"parent\":").Append(Q(t == body ? "" : RigPath(t.parent, body)));
            nodes.Append(",\"pos\":").Append(V2(PosToGodot(t.localPosition)));
            nodes.Append(",\"rot\":").Append(F(RotToGodot(t.localEulerAngles.z)));
            nodes.Append(",\"scale\":").Append(V2(new Vector2(t.localScale.x, t.localScale.y)));
            nodes.Append(",\"visible\":").Append(t.gameObject.activeSelf ? "true" : "false");
            var sr = t.GetComponent<SpriteRenderer>();
            if (sr != null)
            {
                nodes.Append(",\"sprite\":{\"z\":").Append(SortOrder(sr));
                nodes.Append(",\"color\":").Append(Col(sr.color));
                nodes.Append(",\"enabled\":").Append(sr.enabled ? "true" : "false");
                nodes.Append(",\"flip_h\":").Append(sr.flipX ? "true" : "false");
                nodes.Append(",\"flip_v\":").Append(sr.flipY ? "true" : "false");
                nodes.Append(",\"material\":").Append(sr.sharedMaterial ? Q(MaterialKey(sr.sharedMaterial, materials)) : "null");
                nodes.Append(",\"data\":").Append(sr.sprite ? SpriteJson(ctx, sr.sprite) : "null");
                nodes.Append("}");
            }
            var ps = t.GetComponent<ParticleSystem>();
            if (ps != null) nodes.Append(",\"particles\":").Append(ParticlesJson(ctx, ps));
            nodes.Append("}");
        }
        nodes.Append("\n]");

        var cloth = BakeCloth(ctx, body, clips, materials);

        var sb = new StringBuilder();
        sb.Append("{\"format\":2,\"body_type\":").Append(Q(bt.ToString()));
        sb.Append(",\"fps\":").Append(F(SampleFps));
        sb.Append(",\"materials\":").Append(MaterialsJson(materials, ctx));
        sb.Append(",\"nodes\":").Append(nodes);
        sb.Append(",\"cloth\":").Append(cloth);
        sb.Append(",\"segments\":").Append(SegmentsJson(bt));
        sb.Append("}\n");
        WriteRes(ctx, RigRes(bt), sb.ToString());
        ctx.log.AppendLine(string.Format(CI, "Rig {0}: {1} nodes -> {2}", bt, nodeCount, RigRes(bt)));
    }

    // SetupData.bodyTypeData[bt].segmentDatas: what each body slider scales / moves (BodySegmentScaler).
    static string SegmentsJson(BodyType bt)
    {
        var sb = new StringBuilder("{");
        var btd = SetupData.Static.bodyTypeData.Find(d => d.bodyType == bt);
        if (btd == null) return "{}";
        bool first = true;
        foreach (var seg in btd.segmentDatas)
        {
            if (!first) sb.Append(",");
            first = false;
            sb.Append("\n").Append(Q(seg.segmentType.ToString())).Append(":{\"symmetrical\":").Append(seg.symmetrical ? "true" : "false");
            sb.Append(",\"scaled\":[");
            for (int i = 0; i < seg.scaledObjects.Count; i++)
            {
                var o = seg.scaledObjects[i];
                if (i > 0) sb.Append(",");
                sb.Append("{\"path\":").Append(Q(o.objectPath)).Append(",\"def\":").Append(V2(o.defScale))
                  .Append(",\"min\":").Append(V2(o.minScale)).Append(",\"max\":").Append(V2(o.maxScale)).Append("}");
            }
            sb.Append("],\"positioned\":[");
            for (int i = 0; i < seg.positionedObjects.Count; i++)
            {
                var o = seg.positionedObjects[i];
                if (i > 0) sb.Append(",");
                sb.Append("{\"path\":").Append(Q(o.objectPath)).Append(",\"default\":").Append(V2(PosToGodot(o.defaultPos)));
                sb.Append(",\"scale_x\":").Append(o.scaleX ? "true" : "false").Append(",\"min_x\":").Append(V2(PosToGodot(o.minPosX))).Append(",\"max_x\":").Append(V2(PosToGodot(o.maxPosX)));
                sb.Append(",\"scale_y\":").Append(o.scaleY ? "true" : "false").Append(",\"min_y\":").Append(V2(PosToGodot(o.minPosY))).Append(",\"max_y\":").Append(V2(PosToGodot(o.maxPosY)));
                sb.Append("}");
            }
            sb.Append("]}");
        }
        return sb.Append("\n}").ToString();
    }

    static string RigPath(Transform t, Transform body)
    {
        return t == body ? "Root" : "Root/" + PathOf(t, body);
    }

    // A (muzzle flash) particle system: the parts of it CC2D uses. Sizes / speeds / radius in px.
    static string ParticlesJson(Ctx ctx, ParticleSystem ps)
    {
        var m = ps.main;
        var e = ps.emission;
        var sh = ps.shape;
        var r = ps.GetComponent<ParticleSystemRenderer>();
        var t = ps.transform;
        var sb = new StringBuilder("{");
        sb.Append("\"duration\":").Append(F(m.duration));
        sb.Append(",\"loop\":").Append(m.loop ? "true" : "false");
        sb.Append(",\"play_on_awake\":").Append(m.playOnAwake ? "true" : "false");
        sb.Append(",\"local\":").Append(m.simulationSpace == ParticleSystemSimulationSpace.Local ? "true" : "false");
        sb.Append(",\"lifetime\":").Append(MinMax(m.startLifetime, 1f));
        sb.Append(",\"speed\":").Append(MinMax(m.startSpeed, UnitToPx));
        sb.Append(",\"size\":").Append(MinMax(m.startSize, UnitToPx));
        sb.Append(",\"color\":").Append(Col(m.startColor.color));
        int burst = 0;
        for (int i = 0; i < e.burstCount; i++) burst += (int)e.GetBurst(i).count.constant;
        sb.Append(",\"burst\":").Append(burst);
        sb.Append(",\"rate\":").Append(F(e.enabled ? e.rateOverTime.constant : 0f));
        // Emission direction (a cone emits along its local +Z), in the frame of the Godot node, which
        // only carries the transform's Z rotation.
        Vector3 d = Quaternion.Inverse(Quaternion.Euler(0, 0, t.localEulerAngles.z)) * t.localRotation * Quaternion.Euler(sh.rotation) * Vector3.forward;
        Vector2 dir = new Vector2(d.x, -d.y);
        if (dir.sqrMagnitude < 1e-4f) dir = Vector2.right;
        sb.Append(",\"direction\":").Append(V2(dir.normalized));
        sb.Append(",\"spread\":").Append(F(sh.enabled && sh.shapeType == ParticleSystemShapeType.Cone ? sh.angle : 0f));
        sb.Append(",\"radius\":").Append(F(sh.enabled ? sh.radius * UnitToPx : 0f));
        var col = ps.colorOverLifetime;
        sb.Append(",\"color_over_life\":");
        if (col.enabled && col.color.gradient != null)
        {
            sb.Append("[");
            for (int i = 0; i <= 4; i++) { if (i > 0) sb.Append(","); var c = col.color.gradient.Evaluate(i / 4f); sb.Append("[").Append(F(i / 4f)).Append(",").Append(Col(c).Substring(1)); }
            sb.Append("]");
        }
        else sb.Append("null");
        sb.Append(",\"render_mode\":").Append(Q(r.renderMode.ToString()));
        sb.Append(",\"length_scale\":").Append(F(r.lengthScale));
        sb.Append(",\"z\":").Append(SortOrder(r));
        var mat = r.sharedMaterial;
        var tex = mat ? mat.mainTexture as Texture2D : null;
        sb.Append(",\"texture\":").Append(tex ? Q(TextureRes(ctx, tex)) : "null");
        sb.Append(",\"additive\":").Append(mat && mat.shader.name.Contains("Additive") ? "true" : "false");
        sb.Append("}");
        return sb.ToString();
    }

    static string MinMax(ParticleSystem.MinMaxCurve c, float k)
    {
        if (c.mode == ParticleSystemCurveMode.TwoConstants) return "[" + F(c.constantMin * k) + "," + F(c.constantMax * k) + "]";
        return "[" + F(c.constant * k) + "," + F(c.constant * k) + "]";
    }

    static int SortOrder(Renderer r)
    {
        int idx = SetupData.Static.order.IndexOf(r.name);
        return idx >= 0 ? idx : r.sortingOrder; // CharacterViewer.sortSprites
    }

    // Cape / skirt: skinned meshes whose bones use 3D rotations. Godot's 2D bones can't
    // reproduce that, so we evaluate Unity's skinning for every sampled frame of every clip
    // and store vertex positions in the space of the cloth's 2D parent bone.
    static string BakeCloth(Ctx ctx, Transform body, List<KeyValuePair<string, AnimationClip>> clips, Dictionary<Material, string> materials)
    {
        var holder = new GameObject("__cc2d_bake") { hideFlags = HideFlags.HideAndDontSave };
        var sb = new StringBuilder("{");
        try
        {
            var rig = UnityEngine.Object.Instantiate(body, holder.transform);
            rig.name = "Root";
            var all = rig.GetComponentsInChildren<Transform>(true);
            foreach (var t in all) t.gameObject.SetActive(true);
            var restPos = new Vector3[all.Length];
            var restRot = new Quaternion[all.Length];
            var restScale = new Vector3[all.Length];
            for (int i = 0; i < all.Length; i++) { restPos[i] = all[i].localPosition; restRot[i] = all[i].localRotation; restScale[i] = all[i].localScale; }
            Action restore = () =>
            {
                for (int i = 0; i < all.Length; i++) { all[i].localPosition = restPos[i]; all[i].localRotation = restRot[i]; all[i].localScale = restScale[i]; }
            };

            bool firstCloth = true;
            foreach (var smr in rig.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                var mesh = smr.sharedMesh;
                var clothRoot = smr.transform.parent;
                var parent2D = clothRoot.parent;
                string slot = clothRoot.name; // "Cape" / "Skirt"
                var verts = mesh.vertices;
                var weights = mesh.boneWeights;
                var bindposes = mesh.bindposes;
                var bones = smr.bones;

                Func<float[]> compute = () =>
                {
                    var outv = new float[verts.Length * 2];
                    var toLocal = parent2D.worldToLocalMatrix;
                    var mats = new Matrix4x4[bones.Length];
                    for (int b = 0; b < bones.Length; b++) mats[b] = toLocal * bones[b].localToWorldMatrix * bindposes[b];
                    for (int v = 0; v < verts.Length; v++)
                    {
                        var w = weights[v];
                        Vector3 p = mats[w.boneIndex0].MultiplyPoint3x4(verts[v]) * w.weight0
                                  + mats[w.boneIndex1].MultiplyPoint3x4(verts[v]) * w.weight1
                                  + mats[w.boneIndex2].MultiplyPoint3x4(verts[v]) * w.weight2
                                  + mats[w.boneIndex3].MultiplyPoint3x4(verts[v]) * w.weight3;
                        outv[v * 2] = p.x * UnitToPx;
                        outv[v * 2 + 1] = -p.y * UnitToPx;
                    }
                    return outv;
                };

                restore();
                var rest = compute();

                var anims = new StringBuilder("{");
                bool firstAnim = true;
                int baked = 0;
                foreach (var kv in clips)
                {
                    var clip = kv.Value;
                    var times = Times(clip);
                    var frames = new List<float[]>();
                    restore();
                    foreach (var time in times)
                    {
                        clip.SampleAnimation(holder, time);
                        frames.Add(compute());
                    }
                    bool sameAsRest = true, constant = true;
                    for (int f = 0; f < frames.Count && (sameAsRest || constant); f++)
                    {
                        if (MaxDiff(frames[f], rest) > 0.05f) sameAsRest = false;
                        if (MaxDiff(frames[f], frames[0]) > 0.05f) constant = false;
                    }
                    if (sameAsRest) continue;
                    if (!firstAnim) anims.Append(",");
                    firstAnim = false;
                    baked++;
                    anims.Append("\n").Append(Q(kv.Key)).Append(":{\"times\":[");
                    int n = constant ? 1 : times.Count;
                    for (int i = 0; i < n; i++) { if (i > 0) anims.Append(","); anims.Append(F(times[i])); }
                    anims.Append("],\"frames\":[");
                    for (int i = 0; i < n; i++) { if (i > 0) anims.Append(","); anims.Append(Arr(frames[i])); }
                    anims.Append("]}");
                }
                anims.Append("}");
                restore();

                if (!firstCloth) sb.Append(",");
                firstCloth = false;
                var uv = mesh.uv;
                var uvs = new float[uv.Length * 2];
                for (int i = 0; i < uv.Length; i++) { uvs[i * 2] = uv[i].x; uvs[i * 2 + 1] = 1f - uv[i].y; }
                sb.Append("\n").Append(Q(slot)).Append(":{");
                sb.Append("\"parent\":").Append(Q(RigPath(parent2D, rig)));
                sb.Append(",\"node\":").Append(Q(RigPath(clothRoot, rig)));
                sb.Append(",\"z\":").Append(SortOrder(smr));
                sb.Append(",\"material\":").Append(smr.sharedMaterial ? Q(MaterialKey(smr.sharedMaterial, materials)) : "null");
                sb.Append(",\"uv\":").Append(Arr(uvs));
                sb.Append(",\"triangles\":[").Append(string.Join(",", Array.ConvertAll(mesh.triangles, x => x.ToString(CI)))).Append("]");
                sb.Append(",\"rest\":").Append(Arr(rest));
                sb.Append(",\"animations\":").Append(anims);
                sb.Append("}");
                ctx.log.AppendLine(string.Format(CI, "  {0}: {1} verts, {2} animations with cloth motion", slot, verts.Length, baked));
            }
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(holder);
        }
        sb.Append("}");
        return sb.ToString();
    }

    static float MaxDiff(float[] a, float[] b)
    {
        float m = 0f;
        for (int i = 0; i < a.Length; i++) m = Mathf.Max(m, Mathf.Abs(a[i] - b[i]));
        return m;
    }

    // ---------------------------------------------------------------- animations
    static List<KeyValuePair<string, AnimationClip>> ClipsOf(RuntimeAnimatorController rac)
    {
        var clips = new List<KeyValuePair<string, AnimationClip>>();
        var ac = rac as AnimatorController;
        if (ac != null && ac.layers.Length > 0)
        {
            foreach (var cs in ac.layers[0].stateMachine.states)
            {
                var clip = cs.state.motion as AnimationClip;
                if (clip != null) clips.Add(new KeyValuePair<string, AnimationClip>(cs.state.name, clip));
            }
        }
        else
        {
            foreach (var c in rac.animationClips) clips.Add(new KeyValuePair<string, AnimationClip>(c.name, c));
        }
        return clips;
    }

    static List<float> Times(AnimationClip clip)
    {
        float length = Mathf.Max(clip.length, 1f / SampleFps);
        int n = Mathf.Max(1, Mathf.CeilToInt(length * SampleFps - 0.001f));
        var times = new List<float>();
        for (int i = 0; i <= n; i++) times.Add(Mathf.Min(i / SampleFps, length));
        return times;
    }

    static void ExportAnimations(Ctx ctx, List<KeyValuePair<string, AnimationClip>> clips, string res)
    {
        var sprites = new List<Sprite>();
        var sb = new StringBuilder();
        sb.Append("{\"format\":3,\"fps\":").Append(F(SampleFps)).Append(",\"animations\":{");
        bool firstClip = true;
        foreach (var kv in clips)
        {
            if (!firstClip) sb.Append(",");
            firstClip = false;
            sb.Append("\n").Append(Q(kv.Key)).Append(":").Append(ClipJson(ctx, kv.Value, sprites));
        }
        sb.Append("\n}");

        // Extra override layers (CC2D: "Aim Layer" with 1D blend trees over the "Aim" parameter).
        sb.Append(",\"layers\":{");
        var ac = _lastController as AnimatorController;
        bool firstLayer = true;
        if (ac != null)
        {
            for (int li = 1; li < ac.layers.Length; li++)
            {
                var layer = ac.layers[li];
                if (!firstLayer) sb.Append(",");
                firstLayer = false;
                sb.Append("\n").Append(Q(layer.name)).Append(":{\"blending\":").Append(Q(layer.blendingMode.ToString()))
                  .Append(",\"weight\":").Append(F(layer.defaultWeight))
                  .Append(",\"default\":").Append(Q(layer.stateMachine.defaultState ? layer.stateMachine.defaultState.name : ""))
                  .Append(",\"states\":{");
                bool firstState = true;
                foreach (var cs in layer.stateMachine.states)
                {
                    if (!firstState) sb.Append(",");
                    firstState = false;
                    sb.Append("\n").Append(Q(cs.state.name)).Append(":");
                    var bt = cs.state.motion as BlendTree;
                    var clip = cs.state.motion as AnimationClip;
                    if (bt != null)
                    {
                        sb.Append("{\"param\":").Append(Q(bt.blendParameter)).Append(",\"children\":[");
                        for (int i = 0; i < bt.children.Length; i++)
                        {
                            if (i > 0) sb.Append(",");
                            sb.Append("{\"threshold\":").Append(F(bt.children[i].threshold)).Append(",\"anim\":")
                              .Append(ClipJson(ctx, bt.children[i].motion as AnimationClip, sprites)).Append("}");
                        }
                        sb.Append("]}");
                    }
                    else if (clip != null)
                        sb.Append("{\"param\":null,\"children\":[{\"threshold\":0,\"anim\":").Append(ClipJson(ctx, clip, sprites)).Append("}]}");
                    else
                        sb.Append("null");
                }
                sb.Append("}}");
            }
        }
        sb.Append("}");

        // sprite table for sprite-swap tracks
        sb.Append(",\"sprites\":[");
        for (int i = 0; i < sprites.Count; i++) { if (i > 0) sb.Append(","); sb.Append("\n").Append(SpriteJson(ctx, sprites[i])); }
        sb.Append("]}\n");
        WriteRes(ctx, res, sb.ToString());
        ctx.log.AppendLine("Animations: " + clips.Count + " -> " + res + " (" + sprites.Count + " swap sprites)");
    }

    static RuntimeAnimatorController _lastController; // controller being exported (set in ExportShared)

    static string ClipJson(Ctx ctx, AnimationClip clip, List<Sprite> sprites)
    {
        var body = SetupData.Static.GetBodyPrefab(BodyType.Male);
        string capeRoot = SetupData.capeLink.Substring(0, SetupData.capeLink.LastIndexOf('/'));
        string skirtRoot = SetupData.skirtLink.Substring(0, SetupData.skirtLink.LastIndexOf('/'));
        var sb = new StringBuilder();
        if (clip == null) return "null";
        var times = Times(clip);
        // path|prop -> curve. Prefer localEulerAnglesRaw over localEulerAngles.
        var tracks = new Dictionary<string, KeyValuePair<EditorCurveBinding, AnimationCurve>>();
        foreach (var b in AnimationUtility.GetCurveBindings(clip))
        {
            if (InSubtree(b.path, capeRoot) || InSubtree(b.path, skirtRoot)) continue; // baked into rigs
            string prop = PropOf(b);
            if (prop == null)
            {
                if (!IsHarmlessBinding(clip, b)) ctx.Warn("Unsupported animation binding (ignored): " + b.type.Name + "." + b.propertyName);
                continue;
            }
            if (prop != "emote_anim_index" && FindInBody(body, b.path) == null)
            {
                ctx.Warn("Animation path not in any CC2D rig, so it has no effect in Unity either (ignored): " + b.path);
                continue;
            }
            string key = b.path + "|" + prop;
            if (tracks.ContainsKey(key) && !b.propertyName.Contains("Raw")) continue;
            tracks[key] = new KeyValuePair<EditorCurveBinding, AnimationCurve>(b, AnimationUtility.GetEditorCurve(clip, b));
        }

        bool loop = AnimationUtility.GetAnimationClipSettings(clip).loopTime;
        sb.Append("{\"length\":").Append(F(times[times.Count - 1])).Append(",\"loop\":").Append(loop ? "true" : "false").Append(",\"tracks\":[");
        bool firstTrack = true;
        foreach (var tkv in tracks)
        {
            var path = tkv.Value.Key.path;
            var prop = tkv.Key.Substring(tkv.Key.IndexOf('|') + 1);
            var curve = tkv.Value.Value;
            if (!firstTrack) sb.Append(",");
            firstTrack = false;
            if (prop == "emote_anim_index")
            {
                // keep the curve's own stepped keys so very short blinks aren't lost to sampling
                sb.Append("\n {\"path\":\".\",\"prop\":\"emote_anim_index\",\"times\":[");
                for (int i = 0; i < curve.keys.Length; i++) { if (i > 0) sb.Append(","); sb.Append(F(curve.keys[i].time)); }
                sb.Append("],\"values\":[");
                for (int i = 0; i < curve.keys.Length; i++) { if (i > 0) sb.Append(","); sb.Append(F(Mathf.Round(curve.keys[i].value))); }
                sb.Append("]}");
                continue;
            }
            var values = new List<string>();
            foreach (var time in times) values.Add(ConvertValue(prop, curve.Evaluate(time)));
            bool constant = true;
            for (int i = 1; i < values.Count; i++) if (values[i] != values[0]) { constant = false; break; }
            sb.Append("\n {\"path\":").Append(Q(path)).Append(",\"prop\":").Append(Q(prop)).Append(",\"times\":[");
            int n = constant ? 1 : times.Count;
            for (int i = 0; i < n; i++) { if (i > 0) sb.Append(","); sb.Append(F(times[i])); }
            sb.Append("],\"values\":[");
            for (int i = 0; i < n; i++) { if (i > 0) sb.Append(","); sb.Append(values[i]); }
            sb.Append("]}");
        }

        // sprite swaps (SpriteRenderer.m_Sprite object-reference curves) -> index into the sprite table, -1 = none
        foreach (var b in AnimationUtility.GetObjectReferenceCurveBindings(clip))
        {
            if (b.type != typeof(SpriteRenderer) || b.propertyName != "m_Sprite") { ctx.Warn("Unsupported object curve (ignored): " + b.type.Name + "." + b.propertyName); continue; }
            var keys = AnimationUtility.GetObjectReferenceCurve(clip, b);
            if (!firstTrack) sb.Append(",");
            firstTrack = false;
            sb.Append("\n {\"path\":").Append(Q(b.path)).Append(",\"prop\":\"sprite\",\"times\":[");
            for (int i = 0; i < keys.Length; i++) { if (i > 0) sb.Append(","); sb.Append(F(keys[i].time)); }
            sb.Append("],\"values\":[");
            for (int i = 0; i < keys.Length; i++)
            {
                if (i > 0) sb.Append(",");
                var sp = keys[i].value as Sprite;
                if (sp == null) { sb.Append("-1"); continue; }
                int idx = sprites.IndexOf(sp);
                if (idx < 0) { sprites.Add(sp); idx = sprites.Count - 1; }
                sb.Append(idx);
            }
            sb.Append("]}");
        }
        sb.Append("]}");
        return sb.ToString();
    }

    // Bindings we deliberately drop: z components, and x/y euler rotations that never leave 0
    // (these are 2D bones keyed in 3D; the audit found no 180-degree flips).
    static bool IsHarmlessBinding(AnimationClip clip, EditorCurveBinding b)
    {
        if (b.type != typeof(Transform)) return false;
        var p = b.propertyName;
        if (p == "m_LocalPosition.z" || p == "m_LocalScale.z") return true;
        if (p == "localEulerAnglesRaw.x" || p == "localEulerAnglesRaw.y" || p == "localEulerAngles.x" || p == "localEulerAngles.y")
        {
            foreach (var k in AnimationUtility.GetEditorCurve(clip, b).keys)
                if (Mathf.Abs(Mathf.DeltaAngle(k.value, 0f)) > 0.01f) return false;
            return true;
        }
        return false;
    }

    static bool InSubtree(string path, string root) { return path == root || path.StartsWith(root + "/"); }

    static Transform FindInBody(Transform body, string path)
    {
        if (path == "Root") return body;
        return path.StartsWith("Root/") ? body.Find(path.Substring(5)) : null;
    }

    static string PropOf(EditorCurveBinding b)
    {
        if (b.type == typeof(Transform))
        {
            switch (b.propertyName)
            {
                case "m_LocalPosition.x": return "position:x";
                case "m_LocalPosition.y": return "position:y";
                case "m_LocalScale.x": return "scale:x";
                case "m_LocalScale.y": return "scale:y";
                case "localEulerAnglesRaw.z":
                case "localEulerAngles.z":
                case "localEulerAnglesBaked.z": return "rotation";
            }
            return null;
        }
        if (b.type == typeof(GameObject) && b.propertyName == "m_IsActive") return "visible";
        if (b.type == typeof(SpriteRenderer) && b.propertyName == "m_Color.a") return "alpha";
        if (b.type == typeof(CharacterViewer) && b.propertyName == "emoteAnimIndex" && b.path == "") return "emote_anim_index";
        return null;
    }

    static string ConvertValue(string prop, float v)
    {
        switch (prop)
        {
            case "position:x": return F(v * UnitToPx);
            case "position:y": return F(-v * UnitToPx);
            case "rotation": return F(RotToGodot(v));
            case "visible": return v > 0.5f ? "true" : "false";
            default: return F(v);
        }
    }

    // ---------------------------------------------------------------- part catalogue
    static void ExportPartCatalogue(Ctx ctx)
    {
        int partCount = 0, spriteCount = 0;
        var sb = new StringBuilder();
        sb.Append("{\"format\":2");

        sb.Append(",\"links\":{");
        bool f1 = true;
        foreach (var kv in SetupData.partLinks)
        {
            if (!f1) sb.Append(",");
            f1 = false;
            sb.Append("\n").Append(Q(kv.Key.ToString())).Append(":").Append(Dict(kv.Value));
        }
        sb.Append("}");
        sb.Append(",\"weapon_links\":{\"main\":").Append(Dict(SetupData.rWeaponLink))
          .Append(",\"off\":").Append(Dict(SetupData.lWeaponLink))
          .Append(",\"bow\":").Append(Dict(SetupData.bowLink))
          .Append(",\"shield\":").Append(Dict(SetupData.shieldLink)).Append("}");
        sb.Append(",\"colorable_links\":{");
        f1 = true;
        foreach (var kv in SetupData.colorableSpriteLinks)
        {
            if (!f1) sb.Append(",");
            f1 = false;
            sb.Append(Q(kv.Key.ToString())).Append(":[");
            for (int i = 0; i < kv.Value.Count; i++) { if (i > 0) sb.Append(","); sb.Append(Q(kv.Value[i])); }
            sb.Append("]");
        }
        sb.Append("}");
        sb.Append(",\"weapon_fx_links\":{\"MainHand\":").Append(Q(SetupData.weaponFXLinks[SlotCategory.MainHand]))
          .Append(",\"OffHand\":").Append(Q(SetupData.weaponFXLinks[SlotCategory.OffHand])).Append("}");
        sb.Append(",\"cape_link\":").Append(Q(SetupData.capeLink)).Append(",\"skirt_link\":").Append(Q(SetupData.skirtLink));

        // SetupData.defaultMaterials: the material a fresh character uses for each slot
        var defMats = new Dictionary<Material, string>();
        sb.Append(",\"default_slot_materials\":{");
        bool fdm = true;
        foreach (var md in SetupData.Static.defaultMaterials)
        {
            if (md.material == null) continue;
            if (!fdm) sb.Append(",");
            fdm = false;
            sb.Append(Q(md.slotCategory.ToString())).Append(":").Append(Q(MaterialKey(md.material, defMats)));
        }
        sb.Append("},\"default_materials\":").Append(MaterialsJson(defMats, ctx));

        sb.Append(",\"categories\":{");
        bool fc = true;
        foreach (var pack in PartList.Static.partPacks)
        {
            if (!fc) sb.Append(",");
            fc = false;
            sb.Append("\n").Append(Q(pack.category.ToString())).Append(":[");
            bool fp = true;
            foreach (var part in pack.parts)
            {
                if (part == null) continue;
                if (!fp) sb.Append(",");
                fp = false;
                partCount++;
                sb.Append("\n {\"name\":").Append(Q(part.name)).Append(",\"package\":").Append(Q(part.packageName ?? ""));
                sb.Append(",\"body\":[");
                for (int i = 0; i < part.supportedBody.Count; i++) { if (i > 0) sb.Append(","); sb.Append(Q(part.supportedBody[i].ToString())); }
                sb.Append("]");
                var weapon = part as Weapon;
                if (weapon != null)
                {
                    sb.Append(",\"weapon\":").Append(Q(weapon.weaponCategory.ToString()));
                    sb.Append(",\"muzzle\":").Append(V2(PosToGodot(weapon.muzzlePosition)));
                }
                sb.Append(",\"texture\":").Append(part.texture ? Q(TextureRes(ctx, part.texture)) : "null");
                sb.Append(",\"mask\":").Append(part.colorMask ? Q(TextureRes(ctx, part.colorMask)) : "null");
                sb.Append(",\"sprites\":{");
                var seen = new HashSet<string>();
                bool fs = true;
                if (part.sprites != null)
                {
                    foreach (var sp in part.sprites)
                    {
                        if (sp == null || !seen.Add(sp.name)) continue;
                        if (!fs) sb.Append(",");
                        fs = false;
                        spriteCount++;
                        sb.Append(Q(sp.name)).Append(":").Append(SpriteJson(ctx, sp));
                    }
                }
                sb.Append("}}");
            }
            sb.Append("]");
        }
        sb.Append("\n}}\n");
        WriteRes(ctx, "res://cc2d/parts.json", sb.ToString());
        ctx.log.AppendLine(string.Format(CI, "Part catalogue: {0} parts, {1} sprites", partCount, spriteCount));
    }

    // ---------------------------------------------------------------- JSON pieces
    static string MaterialKey(Material m, Dictionary<Material, string> mats)
    {
        string key;
        if (!mats.TryGetValue(m, out key)) { key = m.name; mats[m] = key; }
        return key;
    }

    static string MaterialsJson(Dictionary<Material, string> materials, Ctx ctx)
    {
        var sb = new StringBuilder("{");
        bool first = true;
        foreach (var kv in materials)
        {
            var m = kv.Key;
            if (!first) sb.Append(",");
            first = false;
            string kind = m.shader.name.Contains("Armor") ? "armor" : m.shader.name.Contains("Skin") ? "skin" : "plain";
            sb.Append("\n").Append(Q(kv.Value)).Append(":{\"shader\":").Append(Q(kind));
            sb.Append(",\"tint\":").Append(Col(GetCol(m, "_Color", Color.white)));
            if (kind == "armor")
            {
                sb.Append(",\"color1\":").Append(Col(GetCol(m, "_Color1", Color.gray)));
                sb.Append(",\"color2\":").Append(Col(GetCol(m, "_Color2", Color.gray)));
                sb.Append(",\"color3\":").Append(Col(GetCol(m, "_Color3", Color.gray)));
                var mask = m.HasProperty("_ColorMask") ? m.GetTexture("_ColorMask") as Texture2D : null;
                sb.Append(",\"mask\":").Append(mask ? Q(TextureRes(ctx, mask)) : "null");
            }
            else if (kind == "skin")
            {
                var det = m.HasProperty("_Details") ? m.GetTexture("_Details") as Texture2D : null;
                sb.Append(",\"details\":").Append(det ? Q(TextureRes(ctx, det)) : "null");
                sb.Append(",\"details_color\":").Append(Col(GetCol(m, "_DetailsColor", Color.white)));
            }
            sb.Append("}");
        }
        return sb.Append("\n}").ToString();
    }

    static string SpriteJson(Ctx ctx, Sprite sp)
    {
        var tex = sp.texture;
        var res = TextureRes(ctx, tex);
        float f = SourceScale(tex);
        var r = sp.rect;
        var p = sp.pivot;
        float k = (UnitToPx / sp.pixelsPerUnit) / f;
        var sb = new StringBuilder("{\"texture\":");
        sb.Append(Q(res));
        sb.Append(",\"region\":[").Append(F(r.x * f)).Append(",").Append(F((tex.height - r.y - r.height) * f))
          .Append(",").Append(F(r.width * f)).Append(",").Append(F(r.height * f)).Append("]");
        sb.Append(",\"offset\":").Append(V2(new Vector2(-p.x * f, -(r.height - p.y) * f)));
        sb.Append(",\"px_scale\":").Append(F(k)).Append("}");
        return sb.ToString();
    }

    static string TextureRes(Ctx ctx, Texture2D tex)
    {
        string res;
        if (ctx.textures.TryGetValue(tex, out res)) return res;
        var src = AssetDatabase.GetAssetPath(tex);
        string rel = src.StartsWith(SpritesRoot) ? src.Substring(SpritesRoot.Length) : "other/" + Path.GetFileName(src);
        res = "res://cc2d/textures/" + rel;
        var dst = Path.Combine(ctx.project, "cc2d/textures", rel);
        Directory.CreateDirectory(Path.GetDirectoryName(dst));
        var srcFull = Path.GetFullPath(src);
        if (!File.Exists(dst) || new FileInfo(dst).Length != new FileInfo(srcFull).Length)
        {
            File.Copy(srcFull, dst, true);
            ctx.copied++;
        }
        ctx.textures[tex] = res;
        return res;
    }

    static float SourceScale(Texture2D tex)
    {
        var imp = AssetImporter.GetAtPath(AssetDatabase.GetAssetPath(tex)) as TextureImporter;
        if (imp == null) return 1f;
        int w, h;
        imp.GetSourceTextureWidthAndHeight(out w, out h);
        return tex.width > 0 ? (float)w / tex.width : 1f;
    }

    static string Dict(IDictionary<string, string> d)
    {
        var sb = new StringBuilder("{");
        bool first = true;
        foreach (var kv in d)
        {
            if (!first) sb.Append(",");
            first = false;
            sb.Append(Q(kv.Key)).Append(":").Append(Q(kv.Value));
        }
        return sb.Append("}").ToString();
    }

    static Color GetCol(Material m, string prop, Color fallback) { return m.HasProperty(prop) ? m.GetColor(prop) : fallback; }
    static Vector2 PosToGodot(Vector3 p) { return new Vector2(p.x * UnitToPx, -p.y * UnitToPx); }
    static float RotToGodot(float deg) { return -deg * Mathf.Deg2Rad; }

    static string PathOf(Transform t, Transform root)
    {
        var parts = new List<string>();
        while (t != null && t != root) { parts.Insert(0, t.name); t = t.parent; }
        return string.Join("/", parts.ToArray());
    }

    static string F(float v) { return Math.Round(v, 4).ToString("0.####", CI); }
    static string F2(float v) { return Math.Round(v, 2).ToString("0.##", CI); }
    static string Arr(float[] a)
    {
        var sb = new StringBuilder("[");
        for (int i = 0; i < a.Length; i++) { if (i > 0) sb.Append(","); sb.Append(F2(a[i])); }
        return sb.Append("]").ToString();
    }
    static string V2(Vector2 v) { return "[" + F(v.x) + "," + F(v.y) + "]"; }
    static string Col(Color c) { return "[" + F(c.r) + "," + F(c.g) + "," + F(c.b) + "," + F(c.a) + "]"; }
    static string Q(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (var ch in s)
        {
            if (ch == '"' || ch == '\\') sb.Append('\\').Append(ch);
            else if (ch < 32) sb.Append("\\u").Append(((int)ch).ToString("x4"));
            else sb.Append(ch);
        }
        return sb.Append("\"").ToString();
    }
}

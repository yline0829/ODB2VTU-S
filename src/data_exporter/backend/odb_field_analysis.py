# -*- coding: utf-8 -*-
from __future__ import print_function
import os, sys, csv, math, argparse, traceback
from collections import defaultdict
from odbAccess import openOdb
from odb_export_vtu import parse_bbox, selected_elements, normalize_data, centroid, write_vtu
from odb_export_state import safe_step_name as sanitize


def scalar_from_value(v, token, field_output, component_index):
    if token.upper() == "MISES":
        try:
            q = float(v.mises)
            if math.isfinite(q): return q
        except Exception:
            pass
        arr = normalize_data(v.data)
        if arr is None or len(arr) < 6: return None
        s11,s22,s33,s12,s13,s23 = [float(x) for x in arr[:6]]
        q = 0.5*((s11-s22)**2+(s22-s33)**2+(s33-s11)**2) + 3.0*(s12*s12+s13*s13+s23*s23)
        return math.sqrt(max(q,0.0))
    arr = normalize_data(v.data)
    if arr is None: return None
    if component_index is None:
        if len(arr) != 1: return None
        return float(arr[0])
    if component_index < 0 or component_index >= len(arr): return None
    return float(arr[component_index])


def resolve_field(frame, token):
    tu = str(token).upper()
    if tu == "MISES":
        if "S" not in frame.fieldOutputs:
            raise RuntimeError("S is not available in the selected frame, so Mises cannot be analyzed.")
        return frame.fieldOutputs["S"], None

    if token in frame.fieldOutputs:
        fo = frame.fieldOutputs[token]
        comps = list(getattr(fo,"componentLabels",[]) or [])
        if comps:
            raise RuntimeError("%s is multi-component. Select one of: %s" % (token, ", ".join(str(x) for x in comps)))
        return fo, None

    for name,fo in frame.fieldOutputs.items():
        comps = [str(x) for x in (getattr(fo,"componentLabels",[]) or [])]
        for i,c in enumerate(comps):
            if c.upper() == tu:
                return fo, i
    raise RuntimeError("Field/component not found: %s" % token)


def write_csv(path, fields, rows):
    with open(path,"w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields)
        w.writeheader()
        for r in rows: w.writerow(r)


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--odb",required=True)
    p.add_argument("--instance",required=True)
    p.add_argument("--step",required=True)
    p.add_argument("--frame",type=int,required=True)
    p.add_argument("--field-token",required=True)
    p.add_argument("--bbox",default="")
    p.add_argument("--top-n",type=int,default=10)
    p.add_argument("--rank-stat",choices=["mean","max","min"],default="mean")
    p.add_argument("--direction",choices=["max","min"],default="max")
    p.add_argument("--band-percent",type=float,default=5.0)
    p.add_argument("--outdir",required=True)
    p.add_argument("--export-vtu",type=int,default=1,choices=[0,1])
    p.add_argument("--vtu-scope",choices=["top","band","extreme","all"],default="top")
    p.add_argument("--split-grains",type=int,default=0,choices=[0,1])
    a=p.parse_args()

    odb=None
    try:
        bbox=parse_bbox(a.bbox)
        if not os.path.exists(a.outdir): os.makedirs(a.outdir)
        odb=openOdb(a.odb,readOnly=True)
        if a.instance not in odb.rootAssembly.instances: raise RuntimeError("Instance not found: %s"%a.instance)
        if a.step not in odb.steps: raise RuntimeError("Step not found: %s"%a.step)
        st=odb.steps[a.step]
        if a.frame<0 or a.frame>=len(st.frames): raise RuntimeError("Frame out of range")
        fr=st.frames[a.frame]
        inst=odb.rootAssembly.instances[a.instance]

        # Grain analysis is intentionally restricted to actual grain element sets.
        elems,node_map,grain_ids=selected_elements(inst,"__ALL_GRAINS__",bbox)
        elem_labels=set(int(e.label) for e in elems)
        if not elem_labels: raise RuntimeError("No grain elements remain after the region filter.")
        centers=dict((int(e.label),centroid(e,node_map)) for e in elems)

        fo,comp_idx=resolve_field(fr,a.field_token)
        sub=fo.getSubset(region=inst)
        records=[]
        by_grain=defaultdict(list)
        grain_elements=defaultdict(set)
        by_element=defaultdict(list)

        for v in sub.values:
            elab=getattr(v,"elementLabel",None)
            if elab is None: continue
            elab=int(elab)
            if elab not in elem_labels: continue
            val=scalar_from_value(v,a.field_token,fo,comp_idx)
            if val is None or not math.isfinite(val): continue
            gid=grain_ids.get(elab)
            if gid is None: continue
            ip=getattr(v,"integrationPoint","")
            pos=getattr(v,"position","")
            x,y,z=centers[elab]
            rec={"Value":val,"GrainID":int(gid),"ElementLabel":elab,"IntegrationPoint":ip,
                 "Position":str(pos),"X":x,"Y":y,"Z":z}
            records.append(rec)
            by_grain[int(gid)].append(val)
            grain_elements[int(gid)].add(elab)
            by_element[elab].append(val)

        if not records:
            raise RuntimeError("No element-associated values were found for %s in the selected grain region."%a.field_token)

        rmax=max(records,key=lambda r:r["Value"]); rmin=min(records,key=lambda r:r["Value"])
        stem=os.path.splitext(os.path.basename(a.odb))[0]
        tag="%s_%s_f%06d_%s"%(sanitize(stem),sanitize(a.step),a.frame,sanitize(a.field_token))

        extrema=[]
        for typ,r in [("GLOBAL_MAX",rmax),("GLOBAL_MIN",rmin)]:
            row={"Type":typ,"Variable":a.field_token,"Step":a.step,"Frame":a.frame}
            row.update(r); extrema.append(row)
        extrema_path=os.path.join(a.outdir,tag+"_extrema.csv")
        write_csv(extrema_path,["Type","Variable","Step","Frame","Value","GrainID","ElementLabel","IntegrationPoint","Position","X","Y","Z"],extrema)

        stats=[]
        for gid,vals in by_grain.items():
            els=grain_elements[gid]
            xyz=[centers[e] for e in els]
            nxyz=float(len(xyz))
            stats.append({
                "GrainID":gid,"ElementCount":len(els),"RecordCount":len(vals),
                "Mean":sum(vals)/float(len(vals)),"Min":min(vals),"Max":max(vals),
                "CentroidX":sum(q[0] for q in xyz)/nxyz,
                "CentroidY":sum(q[1] for q in xyz)/nxyz,
                "CentroidZ":sum(q[2] for q in xyz)/nxyz,
            })
        stats.sort(key=lambda r:r["GrainID"])
        stats_path=os.path.join(a.outdir,tag+"_grain_statistics.csv")
        write_csv(stats_path,["GrainID","ElementCount","RecordCount","Mean","Min","Max","CentroidX","CentroidY","CentroidZ"],stats)

        stat_key={"mean":"Mean","max":"Max","min":"Min"}[a.rank_stat]
        reverse=(a.direction=="max")
        ranked=sorted(stats,key=lambda r:r[stat_key],reverse=reverse)
        top=[]
        for rank,r in enumerate(ranked[:max(1,a.top_n)],1):
            q=dict(r); q["Rank"]=rank; q["RankStatistic"]=stat_key; q["RankValue"]=r[stat_key]; top.append(q)
        top_path=os.path.join(a.outdir,tag+"_top_grains.csv")
        write_csv(top_path,["Rank","GrainID","RankStatistic","RankValue","ElementCount","RecordCount","Mean","Min","Max","CentroidX","CentroidY","CentroidZ"],top)

        vals=[r[stat_key] for r in stats]
        lo,hi=min(vals),max(vals); span=hi-lo
        pct=max(0.0,float(a.band_percent))/100.0
        best=hi if reverse else lo
        threshold=(best-pct*span) if reverse else (best+pct*span)
        if reverse:
            band=[r for r in ranked if r[stat_key]>=threshold]
        else:
            band=[r for r in ranked if r[stat_key]<=threshold]
        band_rows=[]
        for rank,r in enumerate(band,1):
            q=dict(r); q["Rank"]=rank; q["RankStatistic"]=stat_key; q["RankValue"]=r[stat_key];
            q["BandPercentOfSpan"]=float(a.band_percent); q["Threshold"]=threshold; band_rows.append(q)
        band_path=os.path.join(a.outdir,tag+"_extreme_band_grains.csv")
        write_csv(band_path,["Rank","GrainID","RankStatistic","RankValue","BandPercentOfSpan","Threshold","ElementCount","RecordCount","Mean","Min","Max","CentroidX","CentroidY","CentroidZ"],band_rows)

        # Optional ParaView-ready VTU.
        #
        # By default the geometry itself is restricted to the requested grains,
        # rather than exporting every grain plus a 0/1 mask. This means ParaView
        # opens only the grains of interest, with no unrelated blue/background
        # grains present.
        analysis_vtu = ""
        split_vtus = []
        if int(a.export_vtu) == 1:
            stat_by_gid = dict((int(r["GrainID"]), r) for r in stats)
            rank_by_gid = dict((int(r["GrainID"]), i+1) for i,r in enumerate(ranked))
            top_gid = set(int(r["GrainID"]) for r in top)
            band_gid = set(int(r["GrainID"]) for r in band_rows)
            selected_extreme = rmax if a.direction == "max" else rmin
            extreme_gid = int(selected_extreme["GrainID"])
            extreme_elab = int(selected_extreme["ElementLabel"])

            if a.vtu_scope == "top":
                selected_gid = set(top_gid)
                scope_suffix = "top%d_grains" % max(1, int(a.top_n))
            elif a.vtu_scope == "band":
                selected_gid = set(band_gid)
                scope_suffix = "extreme_band_grains"
            elif a.vtu_scope == "extreme":
                selected_gid = set([extreme_gid])
                scope_suffix = "extreme_grain_%d" % extreme_gid
            else:
                selected_gid = set(int(r["GrainID"]) for r in stats)
                scope_suffix = "all_analyzed_grains"

            selected_elems = [
                e for e in elems
                if grain_ids.get(int(e.label)) is not None
                and int(grain_ids.get(int(e.label))) in selected_gid
            ]
            if not selected_elems:
                raise RuntimeError("No elements remain for requested VTU grain scope: %s" % a.vtu_scope)

            selected_labels = set(int(e.label) for e in selected_elems)
            selected_grain_ids = dict(
                (int(k), int(v)) for k,v in grain_ids.items()
                if int(k) in selected_labels
            )

            element_field = {}
            grain_mean = {}
            grain_min = {}
            grain_max = {}
            grain_rank_value = {}
            grain_rank = {}
            top_mask = {}
            band_mask = {}
            extreme_elem_mask = {}

            for e in selected_elems:
                elab = int(e.label)
                vals_e = by_element.get(elab, [])
                if vals_e:
                    element_field[elab] = [sum(vals_e)/float(len(vals_e))]
                else:
                    element_field[elab] = [float("nan")]

                gid = selected_grain_ids.get(elab)
                sr = stat_by_gid.get(int(gid)) if gid is not None else None
                if sr is None:
                    grain_mean[elab] = [float("nan")]
                    grain_min[elab] = [float("nan")]
                    grain_max[elab] = [float("nan")]
                    grain_rank_value[elab] = [float("nan")]
                    grain_rank[elab] = [float("nan")]
                    top_mask[elab] = [0.0]
                    band_mask[elab] = [0.0]
                else:
                    gid_i = int(gid)
                    grain_mean[elab] = [float(sr["Mean"])]
                    grain_min[elab] = [float(sr["Min"])]
                    grain_max[elab] = [float(sr["Max"])]
                    grain_rank_value[elab] = [float(sr[stat_key])]
                    grain_rank[elab] = [float(rank_by_gid[gid_i])]
                    top_mask[elab] = [1.0 if gid_i in top_gid else 0.0]
                    band_mask[elab] = [1.0 if gid_i in band_gid else 0.0]
                extreme_elem_mask[elab] = [1.0 if elab == extreme_elab else 0.0]

            field_name = sanitize(a.field_token)
            arrays = {
                field_name: ("cell",1,element_field),
                "GrainMean": ("cell",1,grain_mean),
                "GrainMin": ("cell",1,grain_min),
                "GrainMax": ("cell",1,grain_max),
                "GrainRankValue": ("cell",1,grain_rank_value),
                "GrainRank": ("cell",1,grain_rank),
                "TopNGrainMask": ("cell",1,top_mask),
                "ExtremeBandMask": ("cell",1,band_mask),
                "SelectedExtremeElementMask": ("cell",1,extreme_elem_mask),
            }

            analysis_vtu = os.path.join(a.outdir, tag + "_" + scope_suffix + ".vtu")
            write_vtu(analysis_vtu, selected_elems, node_map, arrays, selected_grain_ids)

            # Optional: create one VTU per selected grain.
            if int(a.split_grains) == 1:
                for gid_i in sorted(selected_gid):
                    ge = [
                        e for e in selected_elems
                        if selected_grain_ids.get(int(e.label)) == int(gid_i)
                    ]
                    if not ge:
                        continue
                    glabels = set(int(e.label) for e in ge)
                    ggids = dict(
                        (lab, selected_grain_ids[lab])
                        for lab in glabels if lab in selected_grain_ids
                    )

                    g_arrays = {}
                    for arr_name, spec in arrays.items():
                        loc,ncomp,vals = spec[:3]
                        if loc != "cell":
                            continue
                        gvals = dict(
                            (lab, vals[lab]) for lab in glabels if lab in vals
                        )
                        g_arrays[arr_name] = ("cell", ncomp, gvals)

                    gp = os.path.join(
                        a.outdir,
                        tag + "_" + scope_suffix + "_Grain%04d.vtu" % int(gid_i)
                    )
                    write_vtu(gp, ge, node_map, g_arrays, ggids)
                    split_vtus.append(gp)

        summary_path=os.path.join(a.outdir,tag+"_summary.txt")
        with open(summary_path,"w") as f:
            f.write("ODB2VTU-S Exporter - Field Extremum Analysis\n")
            f.write("ODB: %s\nStep: %s\nFrame: %d\nVariable: %s\n"%(a.odb,a.step,a.frame,a.field_token))
            f.write("Region BBox: %s\n"%(a.bbox if a.bbox else "All grain elements"))
            f.write("Global MAX: %.12g ; GrainID=%s ; Element=%s ; IP=%s\n"%(rmax["Value"],rmax["GrainID"],rmax["ElementLabel"],rmax["IntegrationPoint"]))
            f.write("Global MIN: %.12g ; GrainID=%s ; Element=%s ; IP=%s\n"%(rmin["Value"],rmin["GrainID"],rmin["ElementLabel"],rmin["IntegrationPoint"]))
            f.write("Grains analyzed: %d\n"%len(stats))
            f.write("Top-N ranking: direction=%s statistic=%s N=%d\n"%(a.direction,stat_key,a.top_n))
            f.write("Extreme band: %.6g%% of grain-stat range ; grains=%d\n"%(a.band_percent,len(band_rows)))
            f.write("\nFiles:\n%s\n%s\n%s\n%s\n"%(extrema_path,stats_path,top_path,band_path))
            if analysis_vtu:
                f.write("VTU scope: %s\n" % a.vtu_scope)
                f.write("Selected VTU grains: %d\n" % len(selected_gid))
                f.write("%s\n" % analysis_vtu)
                if split_vtus:
                    f.write("Per-grain VTUs: %d\n" % len(split_vtus))
                    for gp in split_vtus:
                        f.write("%s\n" % gp)

        print("SUCCESS")
        print("Global MAX = %.12g ; GrainID=%s ; Element=%s ; IP=%s"%(rmax["Value"],rmax["GrainID"],rmax["ElementLabel"],rmax["IntegrationPoint"]))
        print("Global MIN = %.12g ; GrainID=%s ; Element=%s ; IP=%s"%(rmin["Value"],rmin["GrainID"],rmin["ElementLabel"],rmin["IntegrationPoint"]))
        print("Grains analyzed:",len(stats))
        print("Summary:",summary_path)
        if analysis_vtu:
            print("Analysis VTU:", analysis_vtu)
            print("VTU scope:", a.vtu_scope)
            print("Selected grain count:", len(selected_gid))
            if split_vtus:
                print("Per-grain VTUs:", len(split_vtus))
            print("  CellData: %s, GrainID, GrainMean, GrainMin, GrainMax, GrainRankValue, GrainRank, TopNGrainMask, ExtremeBandMask, SelectedExtremeElementMask" % sanitize(a.field_token))
        return 0
    except Exception:
        print("FATAL EXCEPTION:")
        print(traceback.format_exc())
        return 99
    finally:
        try:
            if odb is not None: odb.close()
        except Exception: pass

if __name__=="__main__":
    sys.exit(main())

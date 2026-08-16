#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Per-sample variant calling: 4 paired-end MiSeq amplicon samples vs chrM.
# bwa mem -> samtools -> lofreq (indelqual + call-parallel) -> bcftools -> awk
# Idempotent: existing, complete outputs are left untouched.
# ---------------------------------------------------------------------------

THREADS="${THREADS:-4}"
ROOT="$PWD"

RAW="data/raw"
REF_SRC="data/ref/chrM.fa"

OUT="results"
REFDIR="$OUT/ref"
REF="$REFDIR/chrM.fa"
TMP="$OUT/tmp"
LOG="$OUT/logs"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$OUT" "$REFDIR" "$TMP" "$LOG"
export TMPDIR="$ROOT/$TMP"

# ---- sanity: inputs present ------------------------------------------------
for s in "${SAMPLES[@]}"; do
    for r in 1 2; do
        [ -s "$RAW/${s}_${r}.fq.gz" ] || exit 1
    done
done
[ -s "$REF_SRC" ] || exit 1

# ---- reference: local copy + indexes (all under results/) ------------------
if [ ! -s "$REF" ]; then
    cp "$REF_SRC" "$TMP/chrM.fa.part"
    mv "$TMP/chrM.fa.part" "$REF"
fi

if [ ! -s "$REF.fai" ]; then
    samtools faidx "$REF" 2> "$LOG/samtools_faidx.log"
fi

if [ ! -s "$REF.bwt" ] || [ ! -s "$REF.sa" ] || [ ! -s "$REF.pac" ] \
   || [ ! -s "$REF.ann" ] || [ ! -s "$REF.amb" ]; then
    bwa index "$REF" 2> "$LOG/bwa_index.log"
fi

# ---- per-sample alignment --------------------------------------------------
for s in "${SAMPLES[@]}"; do
    bam="$OUT/$s.bam"

    if [ -s "$bam" ] && [ -s "$bam.bai" ]; then
        continue
    fi

    rm -f "$bam" "$bam.bai" \
          "$TMP/$s.sorted.bam" "$TMP/$s.iq.bam" "$TMP/$s.sort."*

    bwa mem \
        -t "$THREADS" \
        -R "@RG\tID:$s\tSM:$s\tPL:ILLUMINA\tLB:$s\tPU:$s" \
        "$REF" \
        "$RAW/${s}_1.fq.gz" \
        "$RAW/${s}_2.fq.gz" \
        2> "$LOG/$s.bwa_mem.log" \
      | samtools view -@ "$THREADS" -b -u -F 3844 -q 20 - 2> "$LOG/$s.view.log" \
      | samtools sort -@ "$THREADS" -T "$TMP/$s.sort" -o "$TMP/$s.sorted.bam" - \
        2> "$LOG/$s.sort.log"

    # Insert indel qualities so lofreq can call indels on amplicon data.
    lofreq indelqual --dindel -f "$REF" -o "$TMP/$s.iq.bam" "$TMP/$s.sorted.bam" \
        2> "$LOG/$s.indelqual.log"

    mv "$TMP/$s.iq.bam" "$bam"
    samtools index -@ "$THREADS" "$bam" 2> "$LOG/$s.index.log"
    rm -f "$TMP/$s.sorted.bam"
done

# ---- per-sample variant calling -------------------------------------------
for s in "${SAMPLES[@]}"; do
    bam="$OUT/$s.bam"
    vcf="$OUT/$s.vcf.gz"

    if [ -s "$vcf" ] && [ -s "$vcf.tbi" ]; then
        continue
    fi

    rm -f "$vcf" "$vcf.tbi" "$TMP/$s.raw.vcf" "$TMP/$s.rh.vcf" "$TMP/$s.vcf.gz"

    lofreq call-parallel \
        --pp-threads "$THREADS" \
        --call-indels \
        -f "$REF" \
        -o "$TMP/$s.raw.vcf" \
        "$bam" \
        2> "$LOG/$s.lofreq_call.log"

    # Give the VCF proper ##contig lines, then sort/compress/index.
    bcftools reheader --fai "$REF.fai" -o "$TMP/$s.rh.vcf" "$TMP/$s.raw.vcf" \
        2> "$LOG/$s.reheader.log"

    bcftools sort \
        -T "$TMP/${s}.bcfsort" \
        -Oz -o "$TMP/$s.vcf.gz" \
        "$TMP/$s.rh.vcf" \
        2> "$LOG/$s.bcfsort.log"

    mv "$TMP/$s.vcf.gz" "$vcf"
    bcftools index -f -t "$vcf" 2> "$LOG/$s.bcfindex.log"
    rm -f "$TMP/$s.raw.vcf" "$TMP/$s.rh.vcf"
done

# ---- collapsed table -------------------------------------------------------
if [ ! -s "$OUT/collapsed.tsv" ]; then
    rm -f "$TMP/collapsed.tsv"
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query \
                -i 'FILTER="PASS" || FILTER="."' \
                -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "$OUT/$s.vcf.gz" \
                2> "$LOG/$s.query.log" \
              | awk -v smp="$s" 'BEGIN{FS=OFS="\t"} NF>=5 {print smp,$1,$2,$3,$4,$5}'
        done
    } > "$TMP/collapsed.tsv"
    mv "$TMP/collapsed.tsv" "$OUT/collapsed.tsv"
fi

find "$TMP" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
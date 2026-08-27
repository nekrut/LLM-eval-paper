#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUTDIR=results

mkdir -p "$OUTDIR"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

# Helper to skip a step if its output exists and is newer than all inputs
needs_update() {
    local out="$1"
    shift
    for f in "$@"; do
        if [[ ! -e "$out" || "$f" -nt "$out" ]]; then
            return 0   # needs update
        fi
    done
    return 1   # up to date
}

# ---- Per-sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
    fq1="${RAW}/${sample}_1.fq.gz"
    fq2="${RAW}/${sample}_2.fq.gz"
    bam="${OUTDIR}/${sample}.bam"
    bai="${OUTDIR}/${sample}.bam.bai"
    vcf_uncompressed="${OUTDIR}/${sample}.vcf"
    vcf_gz="${OUTDIR}/${sample}.vcf.gz"
    vcf_tbi="${OUTDIR}/${sample}.vcf.gz.tbi"

    # Align with BWA MEM (pipe directly to samtools sort)
    if needs_update "$bam" "$fq1" "$fq2" "$REF" "$REF.fai" "${bai:-}"; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$fq1" "$fq2" |
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # Index BAM if missing or outdated
    if needs_update "$bai" "$bam"; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling with lofreq (skip if VCF already exists and up‑to‑date)
    if needs_update "$vcf_uncompressed" "$bam" "$REF"; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf_uncompressed" "$bam"
    fi

    # Compress & index VCF (skip if already gzipped and indexed)
    if needs_update "$vcf_tbi" "$vcf_uncompressed"; then
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        rm "$vcf_uncompressed"
        tabix -p vcf "$vcf_gz"
    fi
done

# ---- Collapse step ---------------------------------------------------------------
COLLAPSED="${OUTDIR}/collapsed.tsv"
if needs_update "$COLLAPSED" "${SAMPLES[@]}"; do
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            vcf_gz="${OUTDIR}/${sample}.vcf.gz"
            bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
                awk -v s="$sample" '{print s "\t" $0}'
        done
    } > "$COLLAPSED"
fi

# Script ends successfully; no extra output.
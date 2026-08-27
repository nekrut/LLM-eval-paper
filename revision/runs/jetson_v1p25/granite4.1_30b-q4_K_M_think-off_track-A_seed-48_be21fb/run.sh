#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

# Helper to skip a step if its output exists and is newer than all inputs
needs_update() {
    local out=$1; shift
    for f in "$@"; do
        if [[ ! -e "$out" || "$f" -nt "$out" ]]; then
            return 0   # needs update
        fi
    done
    return 1   # up to date
}

# ---- Per-sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
    FASTQ1=data/raw/${sample}_1.fq.gz
    FASTQ2=data/raw/${sample}_2.fq.gz
    BAM=$RESULTS/${sample}.bam
    BAI=$BAM.bai
    VCF=$RESULTS/${sample}.vcf
    VGZ=${VCF}.gz
    VTBI=${VGZ}.tbi

    # Align with bwa mem (pipe directly to samtools sort)
    if needs_update "$BAM" "$FASTQ1" "$FASTQ2" "$REF" "$REF.fai" "$REF.bwt"; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$FASTQ1" "$FASTQ2" |
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # Index BAM if missing or stale
    if needs_update "$BAI" "$BAM"; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with lofreq (skip if VCF already exists and up‑to‑date)
    if needs_update "$VCF" "$BAM" "$REF"; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    fi

    # Compress & index VCF (skip if gz/tbi exist and up‑to‑date)
    if needs_update "$VGZ" "$VCF"; then
        bgzip -c "$VCF" > "$VGZ"
        rm "$VCF"
    fi
    if needs_update "$VTBI" "$VGZ"; then
        tabix -p vcf "$VGZ"
    fi

done

# ---- Collapse step --------------------------------------------------------------
COLLAPSED=$RESULTS/collapsed.tsv
if [[ ! -f "$COLLAPSED" ]] || needs_update "$COLLAPSED" "${SAMPLES[@]/%/.vcf.gz}"; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS/${sample}.vcf.gz" | \
                awk -v s="$sample" '{print s "\t" $0}'
        done
    } > "$COLLAPSED"
fi

# Script ends successfully (no extra output)
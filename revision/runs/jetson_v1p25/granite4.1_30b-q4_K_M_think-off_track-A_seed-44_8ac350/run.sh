#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

# Ensure results directory exists
mkdir -p "$RESULTS"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

# Helper to decide if a target needs regeneration based on timestamps and existence
needs_update() {
    local target=$1; shift
    for src in "$@"; do
        if [[ ! -e "$target" || "$src" -nt "$target" ]]; then
            return 0   # true: update needed
        fi
    done
    return 1   # false: up‑to‑date
}

# ---- Per‑sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
    FASTQ1=data/raw/${sample}_1.fq.gz
    FASTQ2=data/raw/${sample}_2.fq.gz
    BAM=$RESULTS/${sample}.bam
    BAI=$RESULTS/${sample}.bam.bai
    VCF=$RESULTS/${sample}.vcf
    VGZ=$RESULTS/${sample}.vcf.gz
    VTBI=$RESULTS/${sample}.vcf.gz.tbi

    # Align, sort and index if any input newer than BAM or missing
    if needs_update "$BAM" "$FASTQ1" "$FASTQ2" "$REF.bwt"; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$FASTQ1" "$FASTQ2" |
        samtools sort -@ "$THREADS" -o "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling if VCF missing or BAM newer
    if needs_update "$VCF" "$BAM"; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF" -o "$VCF" "$BAM"
        # Compress and index VCF, cleaning up uncompressed version
        bgzip -c "$VCF" > "$VGZ"
        tabix -p vcf "$VGZ"
        rm "$VCF"
    fi
done

# ---- Collapse step -------------------------------------------------------------
COLLAPSED=$RESULTS/collapsed.tsv
if needs_update "$COLLAPSED" "${SAMPLES[@]/%/.vcf.gz}"; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            VGZ=$RESULTS/${sample}.vcf.gz
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VGZ" |
                awk -v s="$sample" '{print s "\t" $0}'
        done
    } > "$COLLAPSED"
fi

# Script ends successfully; no further output
#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
RAW_DIR=data/raw
REF_DIR=data/ref
RESULTS_DIR=results

mkdir -p "$RESULTS_DIR"

# Helper to decide if an output needs updating based on inputs
needs_update() {
    local out=$1
    shift
    [ ! -f "$out" ] && return 0
    for inp in "$@"; do
        [ "$inp" -nt "$out" ] && return 0
    done
    return 1
}

# Reference indexing
ref_fa="$REF_DIR/chrM.fa"
bwa_index_file="$REF_DIR/chrM.fa.bwt"
if needs_update "$bwa_index_file" "$ref_fa"; then
    samtools faidx "$ref_fa"
    bwa index "$ref_fa"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    fq1="$RAW_DIR/${sample}_1.fq.gz"
    fq2="$RAW_DIR/${sample}_2.fq.gz"
    bam="$RESULTS_DIR/${sample}.bam"
    bai="${bam}.bai"
    vcf="$RESULTS_DIR/${sample}.vcf"
    vcf_gz="${vcf}.gz"
    vcf_tbi="${vcf_gz}.tbi"

    # Alignment and sorting
    if needs_update "$bam" "$fq1" "$fq2"; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$ref_fa" "$fq1" "$fq2" |
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # BAM indexing
    if needs_update "$bai" "$bam"; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling
    if needs_update "$vcf_tbi" "$bam"; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$ref_fa" -o "$vcf" "$bam"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Collapse step
collapsed="$RESULTS_DIR/collapsed.tsv"
needs_collapse=0
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    if needs_update "$collapsed" "$vcf_gz"; then
        needs_collapse=1
        break
    fi
done

if ((needs_collapse)); then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
            bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" "$vcf_gz"
        done
    } > "$collapsed"
fi

exit 0
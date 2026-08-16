#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

REF="data/ref/chrM.fa"
REF_FAI="${REF}.fai"
BWA_INDEX_FILES=("${REF}.amb" "${REF}.ann" "${REF}.bwt" "${REF}.pac" "${REF}.sa")

mkdir -p results

# Returns 0 (true) if $1 exists and is not older than any of the remaining args.
is_up_to_date() {
    local target="$1"
    shift
    [[ -e "$target" ]] || return 1
    local f
    for f in "$@"; do
        if [[ "$f" -nt "$target" ]]; then
            return 1
        fi
    done
    return 0
}

# --- Reference indexing (once) ---
if ! is_up_to_date "$REF_FAI" "$REF"; then
    samtools faidx "$REF"
fi

need_bwa_index=false
for f in "${BWA_INDEX_FILES[@]}"; do
    if ! is_up_to_date "$f" "$REF"; then
        need_bwa_index=true
        break
    fi
done
if [[ "$need_bwa_index" == true ]]; then
    bwa index "$REF"
fi

# --- Per-sample processing ---
for sample in "${SAMPLES[@]}"; do
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF="results/${sample}.vcf"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Alignment: SAM -> sorted BAM
    if ! is_up_to_date "$BAM" "$R1" "$R2" "$REF" "${BWA_INDEX_FILES[@]}"; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" \
            | samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # BAM indexing
    if ! is_up_to_date "$BAI" "$BAM"; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with lofreq call-parallel
    if ! is_up_to_date "$VCF_GZ" "$BAM" "$REF" "$REF_FAI"; then
        rm -f "$VCF" "$VCF_GZ" "$TBI"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bgzip -f "$VCF"
    fi

    # VCF indexing
    if ! is_up_to_date "$TBI" "$VCF_GZ"; then
        tabix -f -p vcf "$VCF_GZ"
    fi
done

# --- Collapse step ---
COLLAPSED="results/collapsed.tsv"
VCF_GZ_FILES=()
for sample in "${SAMPLES[@]}"; do
    VCF_GZ_FILES+=("results/${sample}.vcf.gz")
done

if ! is_up_to_date "$COLLAPSED" "${VCF_GZ_FILES[@]}"; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi
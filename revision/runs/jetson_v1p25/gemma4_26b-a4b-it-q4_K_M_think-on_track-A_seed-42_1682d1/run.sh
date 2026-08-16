#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="$RESULTS_DIR/${sample}.bam"
    VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"
    TBI="$VCF_GZ.tbi"

    if [[ ! -f "$TBI" ]] || [[ "$FQ1" -nt "$TBI" ]] || [[ "$FQ2" -nt "$TBI" ]]; then
        RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
        
        bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM"

        samtools index -@ "$THREADS" "$BAM"

        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$RESULTS_DIR/${sample}.vcf" "$BAM"
        
        bgzip "$RESULTS_DIR/${sample}.vcf"
        tabix -p vcf "$VCF_GZ"
    fi
done

COLLAPSED="$RESULTS_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi

exit 0
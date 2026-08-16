#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    VCF_UNCOMPRESSED="results/${sample}.vcf"

    if [[ ! -f "$BAM" ]] || [[ "$FQ1" -nt "$BAM" ]] || [[ "$FQ2" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]] || [[ "$BAM" -nt "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
    
    if [[ -f "$VCF_GZ.tbi" ]] && [[ "$VCF_GZ" -nt "$VCF_GZ.tbi" ]]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

REBUILD_TSV=false
if [[ ! -f "results/collapsed.tsv" ]]; then
    REBUILD_TSV=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "results/${sample}.vcf.gz" -nt "results/collapsed.tsv" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if [ "$REBUILD_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "results/collapsed.tsv"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "results/collapsed.tsv"
    done
fi

exit 0
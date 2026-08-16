#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}
DATA_RAW="data/raw"
DATA_REF="data/ref"
RESULTS="results"

mkdir -p "$RESULTS"

REF="${DATA_REF}/chrM.fa"
[[ ! -f "${REF}.bwt" ]] && bwa index "$REF"
[[ ! -f "${REF}.fai" ]] && samtools faidx "$REF"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"
    
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" \
            "${DATA_RAW}/${SAMPLE}_1.fq.gz" \
            "${DATA_RAW}/${SAMPLE}_2.fq.gz" | \
            samtools view -b -u - | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi
    
    [[ ! -f "$BAI" ]] && samtools index "$BAM"
done

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS}/${SAMPLE}.bam"
    VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${RESULTS}/${SAMPLE}.vcf.gz.tbi"
    
    if [[ ! -f "$VCF_GZ" ]]; then
        VCF="${RESULTS}/${SAMPLE}.vcf"
        lofreq call --ref "$REF" -o "$VCF" "$BAM"
        bgzip -f "$VCF"
        tabix -p vcf "$VCF_GZ"
    fi
    
    [[ ! -f "$VCF_TBI" ]] && tabix -p vcf "$VCF_GZ"
done

COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
            [[ -f "$VCF_GZ" ]] && \
                bcftools query -f "%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" 2>/dev/null || true
        done
    } > "$COLLAPSED"
fi

exit 0
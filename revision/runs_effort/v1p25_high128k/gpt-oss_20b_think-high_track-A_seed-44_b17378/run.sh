#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM=results/${sample}.bam
    VCF_GZ=results/${sample}.vcf.gz
    VCF_TBI=results/${sample}.vcf.gz.tbi

    if [ -f "$VCF_TBI" ]; then
        continue
    fi

    RGLINE="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$RGLINE" \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    VCF=results/${sample}.vcf
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"

    bgzip -c "$VCF" > "${VCF_GZ}"
    tabix -p vcf "$VCF_GZ"
    rm "$VCF"
done

COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
    REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]; then
            REBUILD=true
            break
        fi
    done
fi

if $REBUILD; then
    rm -f "$COLLAPSED"
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        while IFS= read -r line; do
            printf '%s\t%s\n' "$sample" "$line"
        done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz) >> "$COLLAPSED"
    done
fi

exit 0
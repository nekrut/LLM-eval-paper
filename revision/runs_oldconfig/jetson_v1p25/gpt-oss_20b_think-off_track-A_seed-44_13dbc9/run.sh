#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    R1=data/raw/${SAMPLE}_1.fq.gz
    R2=data/raw/${SAMPLE}_2.fq.gz
    BAM=results/${SAMPLE}.bam
    BAI=${BAM}.bai
    VCF_GZ=results/${SAMPLE}.vcf.gz
    VCF_TBI=${VCF_GZ}.tbi

    if [ ! -f "$BAM" ]; then
        bwa mem -t $THREADS -R "@RG\\tID:${SAMPLE}\\tSM:${SAMPLE}\\tLB:${SAMPLE}\\tPL:ILLUMINA" \
            "$R1" "$R2" | samtools sort -@ $THREADS -o "$BAM"
    fi

    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ $THREADS "$BAM"
    fi

    if [ ! -f "$VCF_TBI" ] || [ "$BAM" -nt "$VCF_TBI" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o results/${SAMPLE}.vcf "$BAM"
        bgzip -c results/${SAMPLE}.vcf > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm results/${SAMPLE}.vcf
    fi
done

COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
    REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if find results/${SAMPLE}.vcf.gz.tbi -newer "$COLLAPSED" > /dev/null; then
            REBUILD=true
            break
        fi
    done
fi

if $REBUILD; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${SAMPLE}.vcf.gz >> "$COLLAPSED"
    done
fi

exit 0